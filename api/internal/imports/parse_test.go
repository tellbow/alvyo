package imports

import (
	"bytes"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/muktihari/fit/encoder"
	"github.com/muktihari/fit/profile/filedef"
	"github.com/muktihari/fit/profile/mesgdef"
	"github.com/muktihari/fit/profile/typedef"
)

func TestParseXMLFormats(t *testing.T) {
	for _, tc := range []struct {
		name, file, doc string
		want            []int // points per track
		names           []string
	}{
		{"gpx track with two segments and a route", "tour.gpx", `<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><metadata><name>Meta</name></metadata>
<trk><name>Tag 1</name>
 <trkseg><trkpt lat="46.5" lon="8.0"/><trkpt lat="46.5" lon="8.001"/><trkpt lat="46.5" lon="8.001"/></trkseg>
 <trkseg><trkpt lat="46.5" lon="8.002"/></trkseg></trk>
<rte><rtept lat="46.6" lon="8.1"/><rtept lat="46.6" lon="8.2"/></rte></gpx>`,
			[]int{3, 2}, []string{"Tag 1", "tour 2"}},
		{"gpx with one unnamed track takes the metadata name", "x.gpx", `<gpx><metadata><name>Meta</name></metadata>
<trk><trkseg><trkpt lat="46.5" lon="8.0"/><trkpt lat="46.5" lon="8.001"/></trkseg></trk></gpx>`,
			[]int{2}, []string{"Meta"}},
		{"kml line string and gx:Track", "map.kml", `<?xml version="1.0"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2"><Document>
 <Placemark><name>Linie</name><LineString><coordinates>8.0,46.5,1000 8.001,46.5,1001
  8.002,46.5</coordinates></LineString></Placemark>
 <Placemark><name>Aufzeichnung</name><gx:Track><gx:coord>8.1 46.6 900</gx:coord><gx:coord>8.2 46.6 910</gx:coord></gx:Track></Placemark>
</Document></kml>`,
			[]int{3, 2}, []string{"Linie", "Aufzeichnung"}},
		{"tcx activity with a pause and a course", "run.tcx", `<?xml version="1.0"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
 <Activities><Activity Sport="Other"><Id>2026-07-04T06:00:00Z</Id><Lap><Track>
  <Trackpoint><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.0</LongitudeDegrees></Position></Trackpoint>
  <Trackpoint><Time>2026-07-04T06:01:00Z</Time></Trackpoint>
  <Trackpoint><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.001</LongitudeDegrees></Position></Trackpoint>
 </Track></Lap></Activity></Activities>
 <Courses><Course><Name>Kurs</Name><Track>
  <Trackpoint><Position><LatitudeDegrees>46.6</LatitudeDegrees><LongitudeDegrees>8.1</LongitudeDegrees></Position></Trackpoint>
  <Trackpoint><Position><LatitudeDegrees>46.6</LatitudeDegrees><LongitudeDegrees>8.2</LongitudeDegrees></Position></Trackpoint>
 </Track></Course></Courses></TrainingCenterDatabase>`,
			[]int{2, 2}, []string{"run 1", "Kurs"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, tracks, err := Parse(tc.file, strings.NewReader(tc.doc))
			if err != nil {
				t.Fatal(err)
			}
			if len(tracks) != len(tc.want) {
				t.Fatalf("%d tracks: %+v", len(tracks), tracks)
			}
			for i, tr := range tracks {
				if len(tr.Points) != tc.want[i] || tr.Name != tc.names[i] {
					t.Errorf("track %d: %q with %d points, want %q with %d", i, tr.Name, len(tr.Points), tc.names[i], tc.want[i])
				}
			}
		})
	}
}

func TestParseFIT(t *testing.T) {
	act := filedef.NewActivity()
	start := time.Date(2026, 7, 4, 6, 0, 0, 0, time.UTC)
	act.FileId = *mesgdef.NewFileId(nil).SetType(typedef.FileActivity).SetTimeCreated(start)
	for i := range 5 {
		rec := mesgdef.NewRecord(nil).SetTimestamp(start.Add(time.Duration(i) * time.Second))
		if i != 2 { // a record without position (GPS lost)
			rec.SetPositionLatDegrees(46.5).SetPositionLongDegrees(8.0 + float64(i)*0.001)
		}
		act.Records = append(act.Records, rec)
	}
	f := act.ToFIT(nil)
	var buf bytes.Buffer
	if err := encoder.New(&buf).Encode(&f); err != nil {
		t.Fatal(err)
	}
	format, tracks, err := Parse("watch.fit", &buf)
	if err != nil {
		t.Fatal(err)
	}
	if format != "fit" || len(tracks) != 1 || len(tracks[0].Points) != 4 || tracks[0].Name != "watch" {
		t.Fatalf("%s %+v", format, tracks)
	}
	if p := tracks[0].Points[3]; p.Lon < 8.0039 || p.Lon > 8.0041 || p.Lat < 46.4999 || p.Lat > 46.5001 {
		t.Errorf("last point %+v", p)
	}
	if ts := tracks[0].Times; len(ts) != 4 || !ts[3].Equal(start.Add(4*time.Second)) {
		t.Errorf("times %v", ts)
	}
}

// TestNights splits a recording of three days, with a lunch break, at the
// nights; the times come from GPX, TCX and KML alike.
func TestNights(t *testing.T) {
	day := func(date string, lon float64) string {
		var b strings.Builder
		for i, clock := range []string{"08:00", "10:00", "11:00", "12:00", "16:00"} { // 10–11: lunch
			fmt.Fprintf(&b, `<trkpt lat="46.5" lon="%.3f"><time>%sT%s:00Z</time></trkpt>`, lon+float64(i)*0.001, date, clock)
		}
		return b.String()
	}
	gpx := `<gpx><trk><name>Drei Tage</name><trkseg>` + day("2026-07-04", 8.0) + day("2026-07-05", 8.01) +
		day("2026-07-06", 8.02) + `</trkseg></trk></gpx>`
	_, tracks, err := Parse("x.gpx", strings.NewReader(gpx))
	if err != nil {
		t.Fatal(err)
	}
	days := Nights(tracks[0])
	if len(days) != 3 || len(days[0].Points) != 5 || len(days[2].Points) != 5 || !days[1].Times[0].Equal(time.Date(2026, 7, 5, 8, 0, 0, 0, time.UTC)) {
		t.Fatalf("days: %+v", days)
	}
	// Joined again (e.g. several tracks), the nights stay.
	if n := len(Nights(Join("x", days))); n != 3 {
		t.Errorf("joined: %d days", n)
	}

	// Planned routes have no times: one day.
	_, planned, _ := Parse("p.gpx", strings.NewReader(`<gpx><rte><rtept lat="46.5" lon="8.0"/><rtept lat="46.5" lon="8.1"/></rte></gpx>`))
	if planned[0].Times != nil || len(Nights(planned[0])) != 1 {
		t.Errorf("planned: %+v", planned[0])
	}

	tcx := `<TrainingCenterDatabase><Activities><Activity><Lap><Track>
		<Trackpoint><Time>2026-07-04T16:00:00Z</Time><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.0</LongitudeDegrees></Position></Trackpoint>
		<Trackpoint><Time>2026-07-05T08:00:00Z</Time><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.001</LongitudeDegrees></Position></Trackpoint>
		<Trackpoint><Time>2026-07-05T09:00:00Z</Time><Position><LatitudeDegrees>46.5</LatitudeDegrees><LongitudeDegrees>8.002</LongitudeDegrees></Position></Trackpoint>
		</Track></Lap></Activity></Activities></TrainingCenterDatabase>`
	_, tracks, _ = Parse("x.tcx", strings.NewReader(tcx))
	if n := len(Nights(tracks[0])); n != 2 {
		t.Errorf("tcx: %d days", n)
	}
	kml := `<kml xmlns:gx="http://www.google.com/kml/ext/2.2"><Placemark><gx:Track>
		<when>2026-07-04T16:00:00Z</when><when>2026-07-05T08:00:00Z</when>
		<gx:coord>8.0 46.5 0</gx:coord><gx:coord>8.001 46.5 0</gx:coord></gx:Track></Placemark></kml>`
	_, tracks, _ = Parse("x.kml", strings.NewReader(kml))
	if n := len(Nights(tracks[0])); n != 2 {
		t.Errorf("kml: %d days", n)
	}
}

func TestParseRejects(t *testing.T) {
	for _, doc := range []string{`{"type":"FeatureCollection"}`, `<html><body/></html>`, ``} {
		if _, _, err := Parse("x", strings.NewReader(doc)); !errors.Is(err, ErrFormat) {
			t.Errorf("%q: %v", doc, err)
		}
	}
	if _, _, err := Parse("x.gpx", strings.NewReader(`<gpx><trk><trkseg><trkpt lat="1"`)); err == nil {
		t.Error("broken gpx accepted")
	}
}

func TestParseEncodingsAndComments(t *testing.T) {
	// From older tools: ISO-8859-1 (ü as one byte), or a long comment first.
	latin1 := "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" +
		"<gpx version=\"1.1\"><trk><name>Gr\xfcnhorn</name><trkseg>" +
		"<trkpt lat=\"46.6\" lon=\"8.0\"/><trkpt lat=\"46.61\" lon=\"8.01\"/></trkseg></trk></gpx>"
	commented := "<?xml version=\"1.0\"?>\n<!--" + strings.Repeat(" exported by an old tool ", 60) + "-->\n" +
		"<gpx version=\"1.1\"><trk><name>Alt</name><trkseg>" +
		"<trkpt lat=\"46.6\" lon=\"8.0\"/><trkpt lat=\"46.61\" lon=\"8.01\"/></trkseg></trk></gpx>"
	for want, file := range map[string]string{"Grünhorn": latin1, "Alt": commented} {
		format, tracks, err := Parse("track.gpx", strings.NewReader(file))
		if err != nil || format != "gpx" || len(tracks) != 1 || tracks[0].Name != want || len(tracks[0].Points) != 2 {
			t.Errorf("%s: %s %v %+v", want, format, err, tracks)
		}
	}
}
