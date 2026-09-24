// Package imports turns GPS tracks from files (GPX, KML, TCX, FIT) and from
// Komoot into routes and journeys.
package imports

import (
	"bufio"
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"path"
	"strconv"
	"strings"

	"github.com/muktihari/fit/decoder"
	"github.com/muktihari/fit/profile/filedef"
	"golang.org/x/net/html/charset"

	"github.com/tellbow/odysgeh/swiss/geo"
)

// Limits on uploaded files.
const (
	MaxFileBytes = 20 << 20
	MaxTracks    = 50
)

// ErrFormat means the file is not a track format we read.
var ErrFormat = errors.New("imports: unknown file format")

// Track is one GPS track or planned route.
type Track struct {
	Name   string
	Points []geo.Point
}

// Parse reads the tracks of a GPX, KML, TCX or FIT file. The format comes
// from the content; the file name only helps to name unnamed tracks.
func Parse(filename string, r io.Reader) (format string, tracks []Track, err error) {
	br := bufio.NewReader(io.LimitReader(r, MaxFileBytes+1))
	head, _ := br.Peek(4096) // room for a long comment before the root
	switch {
	case len(head) >= 12 && string(head[8:12]) == ".FIT":
		format = "fit"
		tracks, err = parseFIT(br)
	default:
		root := xmlRoot(head)
		switch root {
		case "gpx":
			format = "gpx"
			tracks, err = parseGPX(br)
		case "kml":
			format = "kml"
			tracks, err = parseKML(br)
		case "TrainingCenterDatabase":
			format = "tcx"
			tracks, err = parseTCX(br)
		default:
			return "", nil, ErrFormat
		}
	}
	if err != nil {
		return format, nil, err
	}
	base := strings.TrimSuffix(path.Base(filename), path.Ext(filename))
	out := tracks[:0]
	for i, t := range tracks {
		t.Points = clean(t.Points)
		if len(t.Points) < 2 {
			continue
		}
		t.Name = strings.TrimSpace(t.Name)
		if t.Name == "" {
			t.Name = base
			if len(tracks) > 1 {
				t.Name += " " + strconv.Itoa(i+1)
			}
		}
		out = append(out, t)
	}
	if len(out) > MaxTracks {
		return format, nil, fmt.Errorf("imports: %d tracks, at most %d", len(out), MaxTracks)
	}
	return format, out, nil
}

// xmlRoot returns the local name of the first element.
func xmlRoot(head []byte) string {
	d := newXMLDecoder(bytes.NewReader(head))
	for {
		tok, err := d.Token()
		if err != nil {
			return ""
		}
		if se, ok := tok.(xml.StartElement); ok {
			return se.Name.Local
		}
	}
}

// newXMLDecoder reads XML in any declared encoding: older tools write GPX
// files in ISO-8859-1 or Windows-1252.
func newXMLDecoder(r io.Reader) *xml.Decoder {
	d := xml.NewDecoder(r)
	d.CharsetReader = charset.NewReaderLabel
	return d
}

// clean drops invalid points and consecutive duplicates.
func clean(pts []geo.Point) []geo.Point {
	out := make([]geo.Point, 0, len(pts))
	for _, p := range pts {
		if math.IsNaN(p.Lon) || math.IsNaN(p.Lat) || p.Lon < -180 || p.Lon > 180 || p.Lat < -90 || p.Lat > 90 ||
			(p.Lon == 0 && p.Lat == 0) {
			continue
		}
		if n := len(out); n > 0 && out[n-1] == p {
			continue
		}
		out = append(out, p)
	}
	return out
}

func parseGPX(r io.Reader) ([]Track, error) {
	type pt struct {
		Lat float64 `xml:"lat,attr"`
		Lon float64 `xml:"lon,attr"`
	}
	var doc struct {
		Name   string `xml:"metadata>name"`
		Tracks []struct {
			Name     string `xml:"name"`
			Segments []struct {
				Points []pt `xml:"trkpt"`
			} `xml:"trkseg"`
		} `xml:"trk"`
		Routes []struct {
			Name   string `xml:"name"`
			Points []pt   `xml:"rtept"`
		} `xml:"rte"`
	}
	if err := newXMLDecoder(r).Decode(&doc); err != nil {
		return nil, fmt.Errorf("imports: gpx: %w", err)
	}
	var out []Track
	for _, t := range doc.Tracks {
		tr := Track{Name: t.Name}
		for _, s := range t.Segments {
			for _, p := range s.Points {
				tr.Points = append(tr.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
			}
		}
		out = append(out, tr)
	}
	for _, rt := range doc.Routes {
		tr := Track{Name: rt.Name}
		for _, p := range rt.Points {
			tr.Points = append(tr.Points, geo.Point{Lon: p.Lon, Lat: p.Lat})
		}
		out = append(out, tr)
	}
	if len(out) == 1 && out[0].Name == "" {
		out[0].Name = doc.Name
	}
	return out, nil
}

// parseKML reads LineStrings and gx:Tracks of all placemarks.
func parseKML(r io.Reader) ([]Track, error) {
	d := newXMLDecoder(r)
	var out []Track
	var name string
	var inPlacemark bool
	for {
		tok, err := d.Token()
		if errors.Is(err, io.EOF) {
			return out, nil
		}
		if err != nil {
			return nil, fmt.Errorf("imports: kml: %w", err)
		}
		se, ok := tok.(xml.StartElement)
		if !ok {
			if ee, ok := tok.(xml.EndElement); ok && ee.Name.Local == "Placemark" {
				inPlacemark, name = false, ""
			}
			continue
		}
		switch se.Name.Local {
		case "Placemark":
			inPlacemark = true
		case "name":
			if inPlacemark {
				var s string
				if err := d.DecodeElement(&s, &se); err != nil {
					return nil, err
				}
				name = s
			}
		case "LineString":
			var ls struct {
				Coordinates string `xml:"coordinates"`
			}
			if err := d.DecodeElement(&ls, &se); err != nil {
				return nil, err
			}
			tr := Track{Name: name}
			for tuple := range strings.FieldsSeq(ls.Coordinates) {
				f := strings.Split(tuple, ",")
				if len(f) < 2 {
					continue
				}
				lon, e1 := strconv.ParseFloat(f[0], 64)
				lat, e2 := strconv.ParseFloat(f[1], 64)
				if e1 == nil && e2 == nil {
					tr.Points = append(tr.Points, geo.Point{Lon: lon, Lat: lat})
				}
			}
			out = append(out, tr)
		case "Track": // gx:Track
			var gt struct {
				Coords []string `xml:"coord"`
			}
			if err := d.DecodeElement(&gt, &se); err != nil {
				return nil, err
			}
			tr := Track{Name: name}
			for _, c := range gt.Coords {
				f := strings.Fields(c)
				if len(f) < 2 {
					continue
				}
				lon, e1 := strconv.ParseFloat(f[0], 64)
				lat, e2 := strconv.ParseFloat(f[1], 64)
				if e1 == nil && e2 == nil {
					tr.Points = append(tr.Points, geo.Point{Lon: lon, Lat: lat})
				}
			}
			out = append(out, tr)
		}
	}
}

// parseTCX reads activities (one track per activity) and courses.
func parseTCX(r io.Reader) ([]Track, error) {
	type trackpoint struct {
		Lat *float64 `xml:"Position>LatitudeDegrees"`
		Lon *float64 `xml:"Position>LongitudeDegrees"`
	}
	var doc struct {
		Activities []struct {
			Laps []struct {
				Points []trackpoint `xml:"Track>Trackpoint"`
			} `xml:"Lap"`
		} `xml:"Activities>Activity"`
		Courses []struct {
			Name   string       `xml:"Name"`
			Points []trackpoint `xml:"Track>Trackpoint"`
		} `xml:"Courses>Course"`
	}
	if err := newXMLDecoder(r).Decode(&doc); err != nil {
		return nil, fmt.Errorf("imports: tcx: %w", err)
	}
	add := func(tr *Track, pts []trackpoint) {
		for _, p := range pts {
			if p.Lat != nil && p.Lon != nil { // pauses have no position
				tr.Points = append(tr.Points, geo.Point{Lon: *p.Lon, Lat: *p.Lat})
			}
		}
	}
	var out []Track
	for _, a := range doc.Activities {
		var tr Track
		for _, l := range a.Laps {
			add(&tr, l.Points)
		}
		out = append(out, tr)
	}
	for _, c := range doc.Courses {
		tr := Track{Name: c.Name}
		add(&tr, c.Points)
		out = append(out, tr)
	}
	return out, nil
}

// parseFIT reads the records of an activity or course file.
func parseFIT(r io.Reader) ([]Track, error) {
	lis := filedef.NewListener()
	defer lis.Close()
	dec := decoder.New(r, decoder.WithMesgListener(lis), decoder.WithBroadcastOnly())
	if _, err := dec.Decode(); err != nil {
		return nil, fmt.Errorf("imports: fit: %w", err)
	}
	var tr Track
	switch f := lis.File().(type) {
	case *filedef.Activity:
		for _, rec := range f.Records {
			tr.Points = append(tr.Points, geo.Point{Lon: rec.PositionLongDegrees(), Lat: rec.PositionLatDegrees()})
		}
	case *filedef.Course:
		if f.Course != nil {
			tr.Name = f.Course.Name
		}
		for _, rec := range f.Records {
			tr.Points = append(tr.Points, geo.Point{Lon: rec.PositionLongDegrees(), Lat: rec.PositionLatDegrees()})
		}
	default:
		return nil, fmt.Errorf("%w: FIT file is neither an activity nor a course", ErrFormat)
	}
	return []Track{tr}, nil
}
