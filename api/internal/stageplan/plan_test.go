package stageplan

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

type flatSampler struct{}

func (flatSampler) Sample(_ context.Context, pts []geo.Point) ([]float64, error) {
	return make([]float64, len(pts)), nil
}

// tunnelGraphHopper answers with the straight line through the points, but
// like GraphHopper by default does not start in a tunnel: the first point
// is moved 180 m off, unless snap_preventions is empty.
func tunnelGraphHopper(t *testing.T) string {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Points          [][2]float64
			SnapPreventions *[]string `json:"snap_preventions"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		coords := [][]float64{}
		for _, p := range req.Points {
			coords = append(coords, []float64{p[0], p[1]})
		}
		if req.SnapPreventions == nil || len(*req.SnapPreventions) > 0 {
			coords[0][1] += 0.0016
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"paths": []any{map[string]any{
			"points":            map[string]any{"coordinates": coords},
			"snapped_waypoints": map[string]any{"coordinates": coords},
		}}})
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

// The way to a place off the line starts on the line, even where the line
// goes through a tunnel (a gallery on the Lötschenpass path).
func TestStageToPlaceFromATunnel(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('hotel', 'Gasthaus', 'osm', 'n1', ST_SetSRID(ST_MakePoint(8.01, 46.505), 4326))`); err != nil {
		t.Fatal(err)
	}
	p := &Planner{DB: pool, Router: &routing.Router{
		GraphHopper: &routing.GraphHopper{URL: tunnelGraphHopper(t)},
		Elevation:   flatSampler{}, Trails: &routing.TrailMatcher{DB: pool},
	}}
	legs := []routing.Leg{testLeg(8.0, 1000, 51, "T2"), testLeg(8.01, 1100, 51, "T3")}
	got, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Stages) != 2 || got.Stages[0].EndPlace == nil || got.Stages[0].EndPlace.Name != "Gasthaus" {
		t.Fatalf("stages: %+v", got.Stages)
	}
}

// A track off the paths (over a glacier): the paths start 110 m from its
// vertex, so the way to a place goes straight, and the stage holds together.
func TestStageToPlaceFromATrackOffThePaths(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('hut', 'Hütte', 'osm', 'n1', ST_SetSRID(ST_MakePoint(8.01, 46.505), 4326))`); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Points [][2]float64 }
		_ = json.NewDecoder(r.Body).Decode(&req)
		coords := [][]float64{}
		for _, p := range req.Points {
			coords = append(coords, []float64{p[0], p[1]})
		}
		coords[0][1] += 0.001 // the nearest path
		_ = json.NewEncoder(w).Encode(map[string]any{"paths": []any{map[string]any{
			"points":            map[string]any{"coordinates": coords},
			"snapped_waypoints": map[string]any{"coordinates": coords},
		}}})
	}))
	t.Cleanup(srv.Close)
	p := &Planner{DB: pool, Router: &routing.Router{
		GraphHopper: &routing.GraphHopper{URL: srv.URL},
		Elevation:   flatSampler{}, Trails: &routing.TrailMatcher{DB: pool},
	}}
	legs := []routing.Leg{testLeg(8.0, 1000, 51, "T2"), testLeg(8.01, 1100, 51, "T3")}
	got, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Stages) != 2 || got.Stages[0].EndPlace == nil || got.Stages[0].EndPlace.Name != "Hütte" {
		t.Fatalf("stages: %+v", got.Stages)
	}
}

func TestSplitEndsAtTheEnds(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	legs := []routing.Leg{testLeg(8.0, 1000, 51, "T2"), testLeg(8.01, 1100, 51, "T3")}
	// Stops at the first and the last vertex, and one in the middle.
	ids := map[string]string{}
	for name, lon := range map[string]float64{"start": 8.0, "middle": 8.01, "end": 8.02} {
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ('pt_stop', $1, 'didok', $1, ST_SetSRID(ST_MakePoint($2, 46.5), 4326)) RETURNING id`, name, lon).Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids[name] = id
	}
	p := &Planner{DB: pool}

	// A day cannot end where the hike starts or ends.
	for _, name := range []string{"start", "end"} {
		if _, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}, Ends: []string{ids[name]}}); !errors.Is(err, ErrUnknownEnd) {
			t.Errorf("ending at the %s: err = %v", name, err)
		}
	}
	got, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}, Ends: []string{ids["middle"]}})
	if err != nil || len(got.Stages) != 2 {
		t.Fatalf("ending in the middle: %d stages, %v", len(got.Stages), err)
	}
}

// A place close to the line but far from it by path (a hut above a cliff)
// is not where a day ends: the Gfellalphütte is 170 m from the Lötschenpass
// path and 20 km by path.
func TestSplitAvoidsPlacesFarByPath(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	for _, pl := range []struct {
		kind, name string
		lon        float64
	}{{"hut", "Fernhütte", 8.0100}, {"hotel", "Gasthaus", 8.0110}} {
		if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'osm', $2, ST_SetSRID(ST_MakePoint($3, 46.5016), 4326))`, pl.kind, pl.name, pl.lon); err != nil {
			t.Fatal(err)
		}
	}
	// Straight lines, but the way to the Fernhütte goes 11 km north first.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct{ Points [][2]float64 }
		_ = json.NewDecoder(r.Body).Decode(&req)
		coords := [][]float64{}
		for _, p := range req.Points {
			coords = append(coords, []float64{p[0], p[1]})
		}
		if last := req.Points[len(req.Points)-1]; last == [2]float64{8.0100, 46.5016} {
			coords = [][]float64{coords[0], {coords[0][0], coords[0][1] + 0.1}, coords[1]}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"paths": []any{map[string]any{
			"points":            map[string]any{"coordinates": coords},
			"snapped_waypoints": map[string]any{"coordinates": [][]float64{coords[0], coords[len(coords)-1]}},
		}}})
	}))
	t.Cleanup(srv.Close)
	p := &Planner{DB: pool, Router: &routing.Router{
		GraphHopper: &routing.GraphHopper{URL: srv.URL},
		Elevation:   flatSampler{}, Trails: &routing.TrailMatcher{DB: pool},
	}}
	legs := []routing.Leg{testLeg(8.0, 1000, 51, "T2"), testLeg(8.01, 1100, 51, "T3")}
	got, err := p.Split(ctx, legs, Request{Profile: "hike", Days: Days{N: 2}})
	if err != nil {
		t.Fatal(err)
	}
	if end := got.Stages[0].EndPlace; end == nil || end.Name != "Gasthaus" {
		t.Errorf("day 1 ends at %+v, want the Gasthaus", end)
	}
	if got.Stages[0].Totals.DistanceM > 3000 {
		t.Errorf("day 1: %.0f m", got.Stages[0].Totals.DistanceM)
	}
}

// Each recorded day is a stage from its first to its last vertex, whether
// it starts where the day before ended or elsewhere (a bus in between), and
// ends at the place where the hiker slept.
func TestByDay(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('hut', 'Hütte', 'osm', 'n1', ST_SetSRID(ST_MakePoint(8.0101, 46.5005), 4326))`); err != nil {
		t.Fatal(err)
	}
	p := &Planner{DB: pool}
	for name, start2 := range map[string]float64{"joined": 8.01, "apart": 8.0113} {
		days := [][]routing.Leg{{testLeg(8.0, 1000, 51, "T2")}, {testLeg(start2, 1100, 51, "T3")}}
		got, err := p.ByDay(ctx, days, "hike")
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if len(got.Stages) != 2 {
			t.Fatalf("%s: %d stages", name, len(got.Stages))
		}
		for i, want := range [][2]float64{{8.0, 8.01}, {start2, start2 + 0.01}} {
			legs := got.Stages[i].Legs
			first, last := legs[0].Coordinates[0], legs[len(legs)-1].Coordinates
			if math.Abs(first[0]-want[0]) > 1e-9 || math.Abs(last[len(last)-1][0]-want[1]) > 1e-9 {
				t.Errorf("%s: stage %d from %v to %v, want %v", name, i+1, first[0], last[len(last)-1][0], want)
			}
		}
		if e := got.Stages[0].EndPlace; e == nil || e.Name != "Hütte" || got.Stages[1].StartPlace == nil {
			t.Errorf("%s: night at %+v", name, e)
		}
	}
}
