// Package gpx writes routes as GPX 1.1 for GPS devices and apps such as the
// swisstopo app.
package gpx

import (
	"encoding/xml"
	"io"
	"strings"
	"time"
	"unicode"
)

// Track is what goes into a GPX file.
type Track struct {
	Name        string
	Description string
	Author      string
	Link        string       // URL of the route page
	Points      [][3]float64 // lon, lat, elevation
	Time        time.Time
}

type gpxFile struct {
	XMLName  xml.Name `xml:"gpx"`
	XMLNS    string   `xml:"xmlns,attr"`
	XSI      string   `xml:"xmlns:xsi,attr"`
	Schema   string   `xml:"xsi:schemaLocation,attr"`
	Version  string   `xml:"version,attr"`
	Creator  string   `xml:"creator,attr"`
	Metadata metadata `xml:"metadata"`
	Trk      trk      `xml:"trk"`
}

// Element order follows the GPX 1.1 schema.
type metadata struct {
	Name      string    `xml:"name"`
	Desc      string    `xml:"desc,omitempty"`
	Author    *author   `xml:"author,omitempty"`
	Copyright copyright `xml:"copyright"`
	Link      *link     `xml:"link,omitempty"`
	Time      string    `xml:"time"`
}

type author struct {
	Name string `xml:"name"`
}

type copyright struct {
	Author  string `xml:"author,attr"`
	License string `xml:"license"`
}

type link struct {
	Href string `xml:"href,attr"`
	Text string `xml:"text"`
}

type trk struct {
	Name   string `xml:"name"`
	Trkseg trkseg `xml:"trkseg"`
}

type trkseg struct {
	Points []trkpt `xml:"trkpt"`
}

type trkpt struct {
	Lat float64 `xml:"lat,attr"`
	Lon float64 `xml:"lon,attr"`
	Ele float64 `xml:"ele"`
}

// Write encodes t as a GPX 1.1 document.
func Write(w io.Writer, t Track) error {
	f := gpxFile{
		XMLNS:   "http://www.topografix.com/GPX/1/1",
		XSI:     "http://www.w3.org/2001/XMLSchema-instance",
		Schema:  "http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd",
		Version: "1.1",
		Creator: "odysgeh",
		Metadata: metadata{
			Name: t.Name,
			Desc: t.Description,
			// Route geometry is derived from OpenStreetMap (ODbL), elevation
			// from swisstopo swissALTI3D.
			Copyright: copyright{Author: "OpenStreetMap contributors, swisstopo", License: "https://opendatacommons.org/licenses/odbl/"},
			Time:      t.Time.UTC().Format(time.RFC3339),
		},
		Trk: trk{Name: t.Name},
	}
	if t.Author != "" {
		f.Metadata.Author = &author{Name: t.Author}
	}
	if t.Link != "" {
		f.Metadata.Link = &link{Href: t.Link, Text: "odysgeh"}
	}
	f.Trk.Trkseg.Points = make([]trkpt, len(t.Points))
	for i, p := range t.Points {
		f.Trk.Trkseg.Points[i] = trkpt{Lat: p[1], Lon: p[0], Ele: p[2]}
	}

	if _, err := io.WriteString(w, xml.Header); err != nil {
		return err
	}
	enc := xml.NewEncoder(w)
	enc.Indent("", " ")
	if err := enc.Encode(f); err != nil {
		return err
	}
	_, err := io.WriteString(w, "\n")
	return err
}

// Filename turns a route title into a safe file name, e.g. "Bachalpsee Runde"
// → "bachalpsee-runde.gpx".
func Filename(title string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(title) {
		switch {
		case r == 'ä':
			b.WriteString("ae")
		case r == 'ö':
			b.WriteString("oe")
		case r == 'ü':
			b.WriteString("ue")
		case r < unicode.MaxASCII && (unicode.IsLetter(r) || unicode.IsDigit(r)):
			b.WriteRune(r)
		default:
			if b.Len() > 0 && !dash {
				b.WriteByte('-')
			}
			dash = true
			continue
		}
		dash = false
	}
	name := strings.Trim(b.String(), "-")
	if name == "" {
		name = "route"
	}
	return name + ".gpx"
}
