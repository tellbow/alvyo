//go:build live

package areas

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

// TestNoticesLive takes a closed trail geo.admin knows of today, walks along
// it and expects it among the notices.
// Run with: go test -tags live ./internal/areas/
func TestNoticesLive(t *testing.T) {
	q := url.Values{
		"geometryType": {"esriGeometryEnvelope"}, "geometry": {"5.9,45.8,10.5,47.8"},
		"layers": {"all:" + closureLayer}, "sr": {"4326"}, "tolerance": {"0"},
		"returnGeometry": {"true"}, "geometryFormat": {"geojson"}, "lang": {"de"},
		"mapExtent": {"5.9,45.8,10.5,47.8"}, "imageDisplay": {"1000,1000,96"}, "limit": {"50"},
	}
	resp, err := http.Get(IdentifyURL + "?" + q.Encode())
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var r identifyResponse
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		t.Fatal(err)
	}
	var line []geo.Point
	var title string
	for _, res := range r.Results {
		var g struct {
			Type        string       `json:"type"`
			Coordinates [][2]float64 `json:"coordinates"`
		}
		if res.Properties["sperrungen_type"] == "closed_way" && json.Unmarshal(res.Geometry, &g) == nil && g.Type == "LineString" {
			for _, c := range g.Coordinates {
				line = append(line, geo.Point{Lon: c[0], Lat: c[1]})
			}
			title, _ = res.Properties["title_de"].(string)
			break
		}
	}
	if len(line) < 2 {
		t.Skip("no closed trail with a simple line today")
	}
	f := &Finder{DB: testdb.New(t), UserAgent: "alvyo-test"}
	got, err := f.Notices(context.Background(), line, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range got {
		if n.Kind == "closure" && n.Title.De == title {
			t.Logf("%s: %s, %s to %s", title, n.Reason.De, n.From, n.To)
			return
		}
	}
	t.Errorf("%q not among %+v", title, got)
}
