package routing

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

// Out uphill, back down: a path due east, a node every 0.005° (about
// 380 m), 10 minutes a node out and 5 back.
func TestReachBack(t *testing.T) {
	var asked []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		asked = append(asked, r.URL.Path+" reverse="+q.Get("reverse_flow")+" limit="+q.Get("time_limit"))
		minutes := 10.0
		if q.Get("reverse_flow") == "true" {
			minutes = 5
		}
		var b strings.Builder
		b.WriteString("node_id,prev_longitude,prev_latitude,longitude,latitude,time\n")
		b.WriteString("0,null,null,9.4,47.0,0\n") // as GraphHopper writes the start
		for i := 1; i <= 60; i++ {
			fmt.Fprintf(&b, "%d,%.3f,47.0,%.3f,47.0,%.0f\n", i, 9.4+float64(i-1)*0.005, 9.4+float64(i)*0.005, float64(i)*minutes*60000)
		}
		_, _ = w.Write([]byte(b.String()))
	}))
	defer srv.Close()
	r := &Router{GraphHopper: &GraphHopper{URL: srv.URL}, Outlines: &Outliner{DB: testdb.New(t)}}

	areas, err := r.ReachBack(context.Background(), geo.Point{Lon: 9.4, Lat: 47.0}, "hike", 1)
	if err != nil {
		t.Fatal(err)
	}
	// Both trees, as far as eight hours reach.
	if len(asked) != 2 || !strings.Contains(strings.Join(asked, " "), "reverse=true limit=28800") ||
		!strings.Contains(strings.Join(asked, " "), "reverse=false limit=28800") {
		t.Errorf("asked %v", asked)
	}
	if len(areas) != 3 || areas[0].Hours != 2 || areas[2].Hours != 8 {
		t.Fatalf("areas %+v", areas)
	}
	east := func(a ReachArea) float64 {
		m := 0.0
		for _, p := range a.Outline[0] {
			m = max(m, p[0])
		}
		return m
	}
	// Two hours there and back: 8 nodes (8 × 15 min), not the 12 one way.
	if e := east(areas[0]); e < 9.44 || e > 9.44+2*cellLon {
		t.Errorf("2 h reach east to %.4f, want about 9.44", e)
	}
	// Eight hours: 32 nodes.
	if e := east(areas[2]); e < 9.56 || e > 9.56+2*cellLon {
		t.Errorf("8 h reach east to %.4f, want about 9.56", e)
	}
}

// The land between paths is filled, a lake stays out, and paths a cell
// apart make one area.
func TestOutline(t *testing.T) {
	o := &Outliner{DB: testdb.New(t)}
	// Cells near Thun: a block of 30 × 30, column and row from i0, j0.
	const i0, j0 = 2560, 23380
	block := func(skip func(i, j int) bool) [][2]int {
		var cells [][2]int
		for i := range 30 {
			for j := range 30 {
				if !skip(i, j) {
					cells = append(cells, [2]int{i0 + i, j0 + j})
				}
			}
		}
		return cells
	}
	rings := func(cells [][2]int) [][][2]float64 {
		t.Helper()
		out, err := o.Outline(context.Background(), cells)
		if err != nil {
			t.Fatal(err)
		}
		return out
	}

	// No path through a few cells here and there: no holes.
	if r := rings(block(func(i, j int) bool { return (i*7+j*3)%11 == 0 })); len(r) != 1 {
		t.Errorf("land between paths: %d rings, want 1", len(r))
	}
	// A lake of 10 × 10 cells (about 5 km²) stays out.
	if r := rings(block(func(i, j int) bool { return i >= 10 && i < 20 && j >= 10 && j < 20 })); len(r) != 2 {
		t.Errorf("lake: %d rings, want 2", len(r))
	}
	// Two halves a column apart: one area across both.
	r := rings(block(func(i, _ int) bool { return i == 15 }))
	west, east := 180.0, 0.0
	for _, p := range r[0] {
		west, east = min(west, p[0]), max(east, p[0])
	}
	if east-west < 29*cellLon {
		t.Errorf("two halves: one area %.4f° wide, want both", east-west)
	}
}
