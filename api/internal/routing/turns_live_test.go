//go:build live

package routing

import (
	"bytes"
	"context"
	"encoding/json"
	"math/rand/v2"
	"net/http"
	"slices"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// TestTurnsLive matches lines onto the dev stack's GraphHopper (:8989) and
// compares the turns with those GraphHopper gives when routing.
// Run with: go test -tags live -run TestTurnsLive -v ./internal/routing/
func TestTurnsLive(t *testing.T) {
	gh := &GraphHopper{URL: "http://localhost:8989"}
	gaflei := geo.Point{Lon: 9.54280, Lat: 47.14472}
	sargans := geo.Point{Lon: 9.44563, Lat: 47.04488}
	line, routed := routedTurns(t, gaflei, sargans)
	want := calm(routed)
	dense, _ := geo.Densify(line, maxVertexSpacing)
	rng := rand.New(rand.NewPCG(1, 2))

	t.Run("planned", func(t *testing.T) {
		found, extra := compare(t, place(line, want), place(dense, turns(t, gh, dense)))
		t.Logf("%d of %d turns found, %d extra", found, len(want), extra)
		if found < len(want)*8/10 || extra > len(want)/10 {
			t.Fail()
		}
	})

	t.Run("planned Gitschenen–Brisenhaus", func(t *testing.T) {
		line, routed := routedTurns(t, geo.Point{Lon: 8.5063, Lat: 46.9318}, geo.Point{Lon: 8.4800, Lat: 46.9119})
		want := calm(routed)
		dense, _ := geo.Densify(line, maxVertexSpacing)
		found, extra := compare(t, place(line, want), place(dense, turns(t, gh, dense)))
		t.Logf("%d of %d turns found, %d extra", found, len(want), extra)
		if found < len(want)*8/10 || extra > len(want)/10+1 {
			t.Fail()
		}
	})

	t.Run("straight leg", func(t *testing.T) {
		// Across the Walensee: no path, so no turns there, but on the rest.
		a, _ := routedTurns(t, geo.Point{Lon: 9.1180, Lat: 47.1270}, geo.Point{Lon: 9.1500, Lat: 47.1275})
		b, _ := routedTurns(t, geo.Point{Lon: 9.1700, Lat: 47.1150}, geo.Point{Lon: 9.2000, Lat: 47.1180})
		da, _ := geo.Densify(a, maxVertexSpacing)
		dl, _ := geo.Densify([]geo.Point{a[len(a)-1], b[0]}, maxVertexSpacing)
		db, _ := geo.Densify(b, maxVertexSpacing)
		line := append(append(slices.Clone(da), dl[1:]...), db[1:]...)
		cum := geo.CumulativeDistance(line)
		lakeFrom, lakeTo := cum[len(da)-1], cum[len(da)+len(dl)-2]
		got := turns(t, gh, line)
		for _, tr := range got {
			if tr.AlongM > lakeFrom+turnCheckM && tr.AlongM < lakeTo-turnCheckM {
				t.Errorf("turn on the lake: %v", tr)
			}
		}
		t.Logf("%d turns, lake %.0f–%.0f m: %v", len(got), lakeFrom, lakeTo, got)
		if len(got) == 0 || got[0].AlongM > lakeFrom || got[len(got)-1].AlongM < lakeTo {
			t.Error("want turns before and after the lake")
		}
	})

	t.Run("gps jitter", func(t *testing.T) {
		// A position every 5 m, as the app uploads them.
		fine, _ := geo.Densify(line, 5)
		noisy := make([]geo.Point, len(fine))
		for i, p := range fine {
			noisy[i] = offset(p, rng.NormFloat64()*6, rng.NormFloat64()*6)
		}
		if got := turns(t, gh, noisy); len(got) != 0 {
			t.Errorf("%d turns on a GPS track", len(got))
		}
	})

	t.Run("gps drift", func(t *testing.T) {
		// A slowly wandering offset, as GPS errors are.
		noisy := make([]geo.Point, len(dense))
		var dx, dy float64
		for i, p := range dense {
			dx = 0.95*dx + rng.NormFloat64()*1.2
			dy = 0.95*dy + rng.NormFloat64()*1.2
			noisy[i] = offset(p, dx, dy)
		}
		got := turns(t, gh, noisy)
		found, extra := compare(t, place(line, want), place(noisy, got))
		t.Logf("%d turns: %d of %d found, %d extra", len(got), found, len(want), extra)
		if extra > len(want)/10 {
			t.Errorf("%d turns that are not there", extra)
		}
	})

	t.Run("out and back", func(t *testing.T) {
		there, back := dense[:len(dense)/3], slices.Clone(dense[:len(dense)/3])
		slices.Reverse(back)
		got := turns(t, gh, append(slices.Clone(there), back[1:]...))
		half := geo.CumulativeDistance(there)[len(there)-1]
		n := 0
		for _, tr := range got {
			if tr.AlongM > half {
				n++
			}
		}
		t.Logf("%d turns, %d on the way back: %v", len(got), n, got)
		if n < (len(got)-n)*8/10 {
			t.Error("turns missing on the way back")
		}
	})
}

func turns(t *testing.T, gh *GraphHopper, line []geo.Point) []Turn {
	t.Helper()
	got, err := gh.Turns(context.Background(), line)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// placed is a turn on the map.
type placed struct {
	at   geo.Point
	kind string
}

func place(line []geo.Point, turns []Turn) []placed {
	cum := geo.CumulativeDistance(line)
	out := make([]placed, len(turns))
	for i, t := range turns {
		out[i] = placed{pointAt(line, cum, t.AlongM), t.Kind}
	}
	return out
}

// compare counts the wanted turns found within 15 m and of the same kind,
// and the turns found that are not wanted.
func compare(t *testing.T, want, got []placed) (found, extra int) {
	near := func(a placed, list []placed) bool {
		for _, b := range list {
			if a.kind == b.kind && geo.Distance(a.at, b.at) <= 15 {
				return true
			}
		}
		return false
	}
	for _, w := range want {
		if near(w, got) {
			found++
		} else {
			t.Logf("missing %v", w)
		}
	}
	for _, g := range got {
		if !near(g, want) {
			extra++
			t.Logf("extra %v", g)
		}
	}
	return found, extra
}

// routedTurns routes from a to b with instructions.
func routedTurns(t *testing.T, a, b geo.Point) ([]geo.Point, []Turn) {
	t.Helper()
	body, _ := json.Marshal(map[string]any{
		"points": [][2]float64{{a.Lon, a.Lat}, {b.Lon, b.Lat}}, "profile": "hike",
		"points_encoded": false, "instructions": true,
	})
	resp, err := http.Post("http://localhost:8989/route", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	var r struct {
		Paths []struct {
			Points struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"points"`
			Instructions []struct {
				Sign     int    `json:"sign"`
				Interval [2]int `json:"interval"`
			} `json:"instructions"`
		} `json:"paths"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil || len(r.Paths) == 0 {
		t.Fatalf("route: %v", err)
	}
	var line []geo.Point
	for _, c := range r.Paths[0].Points.Coordinates {
		line = append(line, geo.Point{Lon: c[0], Lat: c[1]})
	}
	cum := geo.CumulativeDistance(line)
	var out []Turn
	for _, in := range r.Paths[0].Instructions {
		if k, ok := turnKinds[in.Sign]; ok {
			out = append(out, Turn{AlongM: cum[in.Interval[0]], Kind: k})
		}
	}
	return line, out
}
