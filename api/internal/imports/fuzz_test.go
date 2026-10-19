package imports

import (
	"bytes"
	"math"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/muktihari/fit/encoder"
	"github.com/muktihari/fit/profile/filedef"
	"github.com/muktihari/fit/profile/mesgdef"
	"github.com/muktihari/fit/profile/typedef"

	"github.com/tellbow/alvyo/api/internal/gpx"
)

// FuzzParse feeds Parse what anyone can upload. Whatever it accepts must be
// tracks the importer can use. Longer runs: docs/development.md, «Fuzzing».
func FuzzParse(f *testing.F) {
	for _, doc := range []string{
		`<gpx><metadata><name>Meta</name></metadata><trk><name>Tag 1</name><trkseg>
<trkpt lat="46.5" lon="8.0"><time>2026-07-04T06:00:00Z</time></trkpt><trkpt lat="46.5" lon="8.001"/></trkseg></trk>
<rte><rtept lat="46.6" lon="8.1"/><rtept lat="46.6" lon="8.2"/></rte></gpx>`,
		`<?xml version="1.0" encoding="ISO-8859-1"?><!-- a comment --><kml xmlns:gx="http://www.google.com/kml/ext/2.2"><Document>
<Placemark><name>Linie</name><LineString><coordinates>8.0,46.5,1000 8.001,46.5</coordinates></LineString></Placemark>
<Placemark><gx:Track><when>2026-07-04T06:00:00</when><gx:coord>8.1 46.6 900</gx:coord><gx:coord>8.2 46.6 910</gx:coord></gx:Track></Placemark>
</Document></kml>`,
		`<TrainingCenterDatabase><Activities><Activity><Lap><Track>
<Trackpoint><Time>2026-07-04T06:00:00Z</Time><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.0</LongitudeDegrees></Position></Trackpoint>
<Trackpoint><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.001</LongitudeDegrees></Position></Trackpoint>
</Track></Lap></Activity></Activities></TrainingCenterDatabase>`,
	} {
		f.Add([]byte(doc))
	}
	f.Add(fitSeed(f))

	f.Fuzz(func(t *testing.T, data []byte) {
		format, tracks, err := Parse("upload.gpx", bytes.NewReader(data))
		if err != nil {
			return
		}
		if format == "" || len(tracks) > MaxTracks {
			t.Fatalf("format %q, %d tracks", format, len(tracks))
		}
		for _, tr := range tracks {
			if len(tr.Points) < 2 || tr.Name == "" || tr.Name != strings.TrimSpace(tr.Name) {
				t.Fatalf("track %q with %d points", tr.Name, len(tr.Points))
			}
			if tr.Times != nil && len(tr.Times) != len(tr.Points) {
				t.Fatalf("%d times for %d points", len(tr.Times), len(tr.Points))
			}
			for i, p := range tr.Points {
				if math.IsNaN(p.Lon) || math.IsNaN(p.Lat) || math.Abs(p.Lon) > 180 || math.Abs(p.Lat) > 90 {
					t.Fatalf("point %d: %+v", i, p)
				}
				if i > 0 && p == tr.Points[i-1] {
					t.Fatalf("point %d repeats the one before", i)
				}
			}
		}
	})
}

func fitSeed(f *testing.F) []byte {
	act := filedef.NewActivity()
	start := time.Date(2026, 7, 4, 6, 0, 0, 0, time.UTC)
	act.FileId = *mesgdef.NewFileId(nil).SetType(typedef.FileActivity).SetTimeCreated(start)
	for i := range 3 {
		act.Records = append(act.Records, mesgdef.NewRecord(nil).SetTimestamp(start.Add(time.Duration(i)*time.Second)).
			SetPositionLatDegrees(46.5).SetPositionLongDegrees(8.0+float64(i)*0.001))
	}
	fit := act.ToFIT(nil)
	var buf bytes.Buffer
	if err := encoder.New(&buf).Encode(&fit); err != nil {
		f.Fatal(err)
	}
	return buf.Bytes()
}

// FuzzGPXRoundTrip: a route exported as GPX imports again with the same
// name and points.
func FuzzGPXRoundTrip(f *testing.F) {
	f.Add("Bachalpsee Runde", 8.02, 46.67, 0.001, -0.0005, uint8(5))
	f.Add(" «Gratweg» & <Höhe> ", 9.5, 47.1, 0.0, 0.0001, uint8(2))
	f.Fuzz(func(t *testing.T, name string, lon, lat, dLon, dLat float64, n uint8) {
		if math.IsNaN(lon+lat+dLon+dLat) || math.Abs(lon) > 170 || math.Abs(lat) > 80 ||
			math.Abs(dLon) > 0.01 || math.Abs(dLat) > 0.01 || (dLon == 0 && dLat == 0) || n < 2 ||
			!utf8.ValidString(name) { // titles come through JSON and Postgres: valid UTF-8

			t.Skip()
		}
		route := gpx.Track{Name: name, Time: time.Date(2026, 7, 4, 6, 0, 0, 0, time.UTC)}
		for i := range int(n) {
			route.Points = append(route.Points, [3]float64{lon + float64(i)*dLon, lat + float64(i)*dLat, 1000})
		}
		var buf bytes.Buffer
		if err := gpx.Write(&buf, route); err != nil {
			t.Fatal(err)
		}
		_, tracks, err := Parse("export.gpx", &buf)
		if err != nil {
			t.Fatalf("own export refused: %v\n%s", err, buf.Bytes())
		}
		// The importer drops (0, 0) and points equal to the one before.
		var want [][2]float64
		for _, p := range route.Points {
			q := [2]float64{p[0], p[1]}
			if (q != [2]float64{}) && (len(want) == 0 || want[len(want)-1] != q) {
				want = append(want, q)
			}
		}
		if len(want) < 2 {
			return
		}
		if len(tracks) != 1 || len(tracks[0].Points) != len(want) {
			t.Fatalf("%d points in, got %+v", len(want), tracks)
		}
		for i, p := range tracks[0].Points {
			if p.Lon != want[i][0] || p.Lat != want[i][1] {
				t.Fatalf("point %d: %+v, want %v", i, p, want[i])
			}
		}
		// Characters XML cannot hold (controls) come back as U+FFFD.
		xmlName := strings.Map(func(r rune) rune {
			if r < 0x20 && r != '\t' && r != '\n' && r != '\r' || r == 0xFFFE || r == 0xFFFF {
				return utf8.RuneError
			}
			return r
		}, name)
		if wantName := strings.TrimSpace(xmlName); wantName != "" && tracks[0].Name != wantName {
			t.Fatalf("name %q, want %q", tracks[0].Name, wantName)
		}
	})
}
