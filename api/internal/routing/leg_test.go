package routing

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/sac"
)

func TestRuns(t *testing.T) {
	got := runs([]string{"a", "a", "b", "a"})
	want := []Run{{0, 2, "a"}, {2, 3, "b"}, {3, 4, "a"}}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("run %d: %v, want %v", i, got[i], want[i])
		}
	}
}

func TestSmoothTrails(t *testing.T) {
	// 200 m Bergwanderweg, a 20 m blip of Wanderweg (junction), 200 m Bergwanderweg.
	var segs []segment
	for range 10 {
		segs = append(segs, segment{length: 20, trail: sac.Bergwanderweg})
	}
	segs = append(segs, segment{length: 20, trail: sac.Wanderweg})
	for range 10 {
		segs = append(segs, segment{length: 20, trail: sac.Bergwanderweg})
	}
	smoothTrails(segs)
	for i, s := range segs {
		if s.trail != sac.Bergwanderweg {
			t.Errorf("segment %d still %v", i, s.trail)
		}
	}

	// A long run survives.
	segs = []segment{{length: 100, trail: sac.Wanderweg}, {length: 100, trail: sac.Alpinwanderweg}}
	smoothTrails(segs)
	if segs[1].trail != sac.Alpinwanderweg {
		t.Error("long run merged")
	}
}

func TestApplyDetails(t *testing.T) {
	segs := make([]segment, 6)
	orig := []int{0, 3, 6} // 3 original vertices densified to 7
	applyDetails(segs, orig, map[string][]interval{
		"hike_rating": {{0, 1, "0"}, {1, 2, "3"}},
		"road_class":  {{0, 2, "path"}},
	})
	for k, s := range segs {
		want := 0
		if k >= 3 {
			want = 3
		}
		if s.osmSAC != want || s.roadClass != "path" {
			t.Errorf("segment %d: %+v", k, s)
		}
	}
}

// slopeSampler gives a steady climb of 1 m per vertex.
type slopeSampler struct{}

func (slopeSampler) Sample(_ context.Context, pts []geo.Point) ([]float64, error) {
	h := make([]float64, len(pts))
	for i := range h {
		h[i] = 2000 + float64(i)
	}
	return h, nil
}

type failingSampler struct{}

func (failingSampler) Sample(context.Context, []geo.Point) ([]float64, error) {
	return nil, errors.New("boom")
}

func fixtureServer(t *testing.T) *httptest.Server {
	body, err := os.ReadFile("testdata/gh_first_bachalpsee.json")
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/route" || r.Method != http.MethodPost {
			t.Errorf("unexpected %s %s", r.Method, r.URL.Path)
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(srv.Close)
	return srv
}

var (
	first     = geo.Point{Lon: 8.0535, Lat: 46.6597}
	bachalpse = geo.Point{Lon: 8.0247, Lat: 46.6703}
)

func TestLegFromFixture(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	// Mark the middle part of the fixture route (vertices 20–100) as an
	// official Bergwanderweg.
	lons, lats := fixtureCoords(t, 20, 101)
	if _, err := pool.Exec(ctx, `
		INSERT INTO tlm_hiking_paths (id, category, geom)
		VALUES (1, 'Bergwanderweg', ST_Multi(ST_Transform(ST_SetSRID(ST_MakeLine(ARRAY(
			SELECT ST_MakePoint(lon, lat) FROM unnest($1::float8[], $2::float8[]) AS t(lon, lat))), 4326), 2056)))`,
		lons, lats); err != nil {
		t.Fatal(err)
	}

	r := &Router{
		GraphHopper: &GraphHopper{URL: fixtureServer(t).URL},
		Elevation:   slopeSampler{},
		Trails:      &TrailMatcher{DB: pool},
	}
	leg, err := r.Leg(ctx, LegRequest{From: first, To: bachalpse, Profile: "hike"})
	if err != nil {
		t.Fatal(err)
	}

	if leg.DistanceM < 2800 || leg.DistanceM > 3000 {
		t.Errorf("distance %.0f m, GraphHopper said ~2877", leg.DistanceM)
	}
	for i := 1; i < len(leg.Coordinates); i++ {
		a := geo.Point{Lon: leg.Coordinates[i-1][0], Lat: leg.Coordinates[i-1][1]}
		b := geo.Point{Lon: leg.Coordinates[i][0], Lat: leg.Coordinates[i][1]}
		if d := geo.Distance(a, b); d > maxVertexSpacing+0.5 {
			t.Fatalf("vertex spacing %.1f m at %d", d, i)
		}
	}
	if leg.AscentM <= 0 || leg.DurationS <= leg.DurationReverseS {
		t.Errorf("climbing leg: ascent %.0f, up %ds, down %ds", leg.AscentM, leg.DurationS, leg.DurationReverseS)
	}
	if leg.Trails["Bergwanderweg"] < 500 {
		t.Errorf("trails %v: TLM match missing", leg.Trails)
	}
	// OSM rates the end T2; the Bergwanderweg part without OSM value is T2–T3.
	if leg.SAC.Grade != 2 || leg.SAC.Max != 3 {
		t.Errorf("SAC T%d–T%d, want T2–T3 (%v)", leg.SAC.Grade, leg.SAC.Max, leg.SAC.Breakdown)
	}
	if total := sum(leg.Surfaces); math.Abs(total-leg.DistanceM) > 5 {
		t.Errorf("surface breakdown sums to %.0f, distance %.0f", total, leg.DistanceM)
	}
	last := leg.Details.SAC[len(leg.Details.SAC)-1]
	if last.To != len(leg.Coordinates)-1 {
		t.Errorf("SAC runs end at %d, want %d", last.To, len(leg.Coordinates)-1)
	}
	if leg.Snap.FromM > 5 || len(leg.Warnings) != 0 {
		t.Errorf("snap %+v warnings %v", leg.Snap, leg.Warnings)
	}
}

func TestStraightLeg(t *testing.T) {
	pool := testdb.New(t)
	r := &Router{Elevation: slopeSampler{}, Trails: &TrailMatcher{DB: pool}} // no GraphHopper needed
	leg, err := r.Leg(context.Background(), LegRequest{From: first, To: bachalpse, Straight: true})
	if err != nil {
		t.Fatal(err)
	}
	if d := geo.Distance(first, bachalpse); math.Abs(leg.DistanceM-d) > 1 {
		t.Errorf("straight distance %.1f, want %.1f", leg.DistanceM, d)
	}
	// Off-network straight lines get a cautious, unofficial guess.
	if leg.SAC.Grade != 2 || leg.SAC.UnofficialM < leg.DistanceM-1 {
		t.Errorf("straight line off-network: T%d, unofficial %.0f of %.0f m", leg.SAC.Grade, leg.SAC.UnofficialM, leg.DistanceM)
	}
}

func TestLegElevationError(t *testing.T) {
	pool := testdb.New(t)
	r := &Router{GraphHopper: &GraphHopper{URL: fixtureServer(t).URL}, Elevation: failingSampler{}, Trails: &TrailMatcher{DB: pool}}
	if _, err := r.Leg(context.Background(), LegRequest{From: first, To: bachalpse, Profile: "hike"}); !errors.Is(err, ErrElevation) {
		t.Errorf("err = %v, want ErrElevation", err)
	}
}

func TestGraphHopperErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"message":"Cannot find point 1","hints":[{"details":"com.graphhopper.util.exceptions.PointNotFoundException"}]}`))
	}))
	defer srv.Close()
	_, err := (&GraphHopper{URL: srv.URL}).route(context.Background(), first, bachalpse, "hike")
	if !errors.Is(err, ErrPointNotFound) {
		t.Errorf("err = %v", err)
	}
}

// fixtureCoords returns the lons and lats of fixture vertices [from, to).
func fixtureCoords(t *testing.T, from, to int) ([]float64, []float64) {
	body, err := os.ReadFile("testdata/gh_first_bachalpsee.json")
	if err != nil {
		t.Fatal(err)
	}
	var r ghResponse
	if err := json.Unmarshal(body, &r); err != nil {
		t.Fatal(err)
	}
	var lons, lats []float64
	for _, c := range r.Paths[0].Points.Coordinates[from:to] {
		lons = append(lons, c[0])
		lats = append(lats, c[1])
	}
	return lons, lats
}

func sum(m map[string]float64) float64 {
	s := 0.0
	for _, v := range m {
		s += v
	}
	return s
}

func TestTrack(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	r := &Router{Elevation: slopeSampler{}, Trails: &TrailMatcher{DB: pool}}
	// 5.3 km due east at 46.5° N: legs of 2 km, 2 km and 1.3 km.
	const lonPerKm = 1 / (111.195 * 0.68835) // cos(46.5°)
	var pts []geo.Point
	for i := 0; i <= 53; i++ {
		pts = append(pts, geo.Point{Lon: 8 + float64(i)*0.1*lonPerKm, Lat: 46.5})
	}
	legs, err := r.Track(ctx, pts, 2000)
	if err != nil {
		t.Fatal(err)
	}
	if len(legs) != 3 {
		t.Fatalf("%d legs", len(legs))
	}
	total := 0.0
	for i, l := range legs {
		total += l.DistanceM
		if i > 0 && l.Coordinates[0] != legs[i-1].Coordinates[len(legs[i-1].Coordinates)-1] {
			t.Errorf("leg %d does not start where leg %d ends", i, i-1)
		}
		if n := len(l.Details.Trail); n == 0 || l.Details.Trail[n-1].To != len(l.Coordinates)-1 {
			t.Errorf("leg %d detail runs %+v", i, l.Details.Trail)
		}
		// Off the official network, the SAC grade is a guess.
		if l.SAC.Grade != 2 || l.SAC.UnofficialM == 0 {
			t.Errorf("leg %d SAC %+v", i, l.SAC)
		}
	}
	if total < 5250 || total > 5350 || legs[0].DistanceM < 1990 || legs[2].DistanceM > 1400 {
		t.Errorf("distances: total %.0f, first %.0f, last %.0f", total, legs[0].DistanceM, legs[2].DistanceM)
	}

	// A short rest (< a quarter leg) joins the last leg.
	legs, err = r.Track(ctx, pts[:43], 2000) // 4.2 km
	if err != nil || len(legs) != 2 || legs[1].DistanceM < 2100 {
		t.Errorf("rest joined: %d legs, %v", len(legs), err)
	}
}

// alternativesServer answers alternative_route requests with a path along
// 46.66° N and one bulging north to 46.67°, and via requests with the path
// through the given points.
func alternativesServer(t *testing.T) (*httptest.Server, *[]int) {
	var calls []int // points per request; negative with alternatives
	path := func(pts ...[2]float64) map[string]any {
		coords := make([][]float64, len(pts))
		for i, p := range pts {
			coords[i] = []float64{p[0], p[1]}
		}
		return map[string]any{
			"points":            map[string]any{"coordinates": coords},
			"snapped_waypoints": map[string]any{"coordinates": [][]float64{coords[0], coords[len(coords)-1]}},
		}
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Points    [][2]float64 `json:"points"`
			Algorithm string       `json:"algorithm"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		var paths []map[string]any
		if req.Algorithm == "alternative_route" {
			calls = append(calls, -len(req.Points))
			paths = append(paths,
				path([2]float64{8.00, 46.66}, [2]float64{8.02, 46.66}),
				path([2]float64{8.00, 46.66}, [2]float64{8.01, 46.67}, [2]float64{8.02, 46.66}))
		} else {
			calls = append(calls, len(req.Points))
			paths = append(paths, path(req.Points...))
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"paths": paths})
	}))
	t.Cleanup(srv.Close)
	return srv, &calls
}

func TestLegThrough(t *testing.T) {
	pool := testdb.New(t)
	srv, calls := alternativesServer(t)
	r := &Router{GraphHopper: &GraphHopper{URL: srv.URL}, Elevation: slopeSampler{}, Trails: &TrailMatcher{DB: pool}}
	from, to := geo.Point{Lon: 8.00, Lat: 46.66}, geo.Point{Lon: 8.02, Lat: 46.66}
	passes := func(leg Leg, p geo.Point) bool {
		for _, c := range leg.Coordinates {
			if geo.Distance(p, geo.Point{Lon: c[0], Lat: c[1]}) < 15 {
				return true
			}
		}
		return false
	}

	// Released 50 m off the northern alternative: that one is taken.
	near := geo.Point{Lon: 8.01, Lat: 46.6695}
	leg, err := r.Leg(context.Background(), LegRequest{From: from, To: to, Profile: "hike", Through: &near})
	if err != nil {
		t.Fatal(err)
	}
	if !passes(leg, geo.Point{Lon: 8.01, Lat: 46.67}) || len(*calls) != 1 || (*calls)[0] != -2 {
		t.Errorf("northern alternative not taken (calls %v)", *calls)
	}

	// Released where no alternative passes: the leg goes through the point.
	*calls = nil
	far := geo.Point{Lon: 8.01, Lat: 46.65}
	leg, err = r.Leg(context.Background(), LegRequest{From: from, To: to, Profile: "hike", Through: &far})
	if err != nil {
		t.Fatal(err)
	}
	if !passes(leg, far) || len(*calls) != 2 || (*calls)[1] != 3 {
		t.Errorf("leg not routed through the point (calls %v)", *calls)
	}
	if leg.Snap.FromM > 1 || leg.Snap.ToM > 1 {
		t.Errorf("snap %+v: from the first and last waypoint", leg.Snap)
	}
}
