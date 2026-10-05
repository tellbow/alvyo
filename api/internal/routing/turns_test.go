package routing

import (
	"context"
	"encoding/json"
	"math"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"os"
	"slices"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// matchServer answers map matching with the recorded answer for the line
// Gitschenen–Brisenhaus (see fixtureLine).
func matchServer(t *testing.T) (*httptest.Server, [][]float64) {
	body, err := os.ReadFile("testdata/gh_match_gitschenen_brisenhaus.json")
	if err != nil {
		t.Fatal(err)
	}
	var r struct {
		Paths []struct {
			Points struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"points"`
		} `json:"paths"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/match" || r.Header.Get("Content-Type") != "application/gpx+xml" ||
			r.URL.Query().Get("profile") != "alpine" || r.URL.Query().Get("instructions") != "true" {
			t.Errorf("unexpected %s %s %s", r.Method, r.URL, r.Header.Get("Content-Type"))
		}
		_, _ = w.Write(body)
	}))
	t.Cleanup(srv.Close)
	return srv, r.Paths[0].Points.Coordinates
}

// fixtureLine is the planned line Gitschenen–Brisenhaus, densified to 20 m.
func fixtureLine(t *testing.T) []geo.Point {
	body, err := os.ReadFile("testdata/line_gitschenen_brisenhaus.json")
	if err != nil {
		t.Fatal(err)
	}
	var cs [][2]float64
	if err := json.Unmarshal(body, &cs); err != nil {
		t.Fatal(err)
	}
	line := make([]geo.Point, len(cs))
	for i, c := range cs {
		line[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	return line
}

func TestTurnsFromFixture(t *testing.T) {
	srv, coords := matchServer(t)
	got, err := (&GraphHopper{URL: srv.URL}).Turns(context.Background(), fixtureLine(t))
	if err != nil {
		t.Fatal(err)
	}
	// The line is the path, so each turn is as far along the line as it is
	// along the path (instructions at path vertices 2, 3, 99, …).
	path := make([]geo.Point, len(coords))
	for i, c := range coords {
		path[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	cum := geo.CumulativeDistance(path)
	want := []struct {
		at   int
		kind string
	}{
		{2, "sharp_right"}, {3, "right"}, {99, "left"}, {126, "slight_left"}, {132, "keep_right"}, {200, "sharp_left"},
		{214, "right"}, {235, "slight_right"}, {237, "left"}, {362, "sharp_right"}, {385, "keep_right"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %d turns %v, want %d", len(got), got, len(want))
	}
	for i, w := range want {
		if got[i].Kind != w.kind || math.Abs(got[i].AlongM-cum[w.at]) > 2 {
			t.Errorf("turn %d = %+v, want %s at %.1f m", i, got[i], w.kind, cum[w.at])
		}
	}
}

func TestTurnsOfGPSTrack(t *testing.T) {
	// The same path, but the line a GPS track along it: a position every
	// 5 m, off by some metres each; ten tracks, as one may pass by luck.
	srv, _ := matchServer(t)
	line := fixtureLine(t)
	for seed := range uint64(10) {
		fine, _ := geo.Densify(line, 5)
		rng := rand.New(rand.NewPCG(seed+1, 2))
		for i, p := range fine {
			fine[i] = offset(p, rng.NormFloat64()*6, rng.NormFloat64()*6)
		}
		got, err := (&GraphHopper{URL: srv.URL}).Turns(context.Background(), fine)
		if err != nil || len(got) != 0 {
			t.Errorf("track %d: got %v, %v; want no turns", seed+1, got, err)
		}
	}
}

func TestTurnsUnmatched(t *testing.T) {
	for _, tc := range []struct {
		status  int
		wantErr bool
	}{
		{http.StatusBadRequest, false}, // cannot be matched: no turns
		{http.StatusInternalServerError, true},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(tc.status)
			_, _ = w.Write([]byte(`{"message":"Sequence is broken for submitted track at time step 3"}`))
		}))
		got, err := (&GraphHopper{URL: srv.URL}).Turns(context.Background(), fixtureLine(t))
		srv.Close()
		if (err != nil) != tc.wantErr || len(got) != 0 {
			t.Errorf("%d: got %v, %v", tc.status, got, err)
		}
	}
}

func TestTurnsEmptyMatch(t *testing.T) {
	// A match without a line gives no turns rather than a crash.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"paths":[{"points":{"coordinates":[]},"instructions":[{"sign":2,"interval":[0,0]}]}]}`))
	}))
	defer srv.Close()
	got, err := (&GraphHopper{URL: srv.URL}).Turns(context.Background(), fixtureLine(t))
	if err != nil || len(got) != 0 {
		t.Errorf("got %v, %v; want no turns", got, err)
	}
}

func TestCalm(t *testing.T) {
	got := calm([]Turn{
		{100, "right"}, {108, "slight_left"}, // across a road
		{300, "left"}, {310, "keep_left"}, // both left: kept
		{500, "u_turn"}, {505, "u_turn"}, // back and forth
		{700, "right"}, {720, "left"}, // far enough apart
	})
	want := []Turn{{300, "left"}, {310, "keep_left"}, {700, "right"}, {720, "left"}}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestFinderOutAndBack(t *testing.T) {
	// 1 km east and back: on the way back, points are found there, not on
	// the way out.
	there, _ := geo.Densify([]geo.Point{{Lon: 8, Lat: 46.5}, {Lon: 8.013, Lat: 46.5}}, 20)
	back := slices.Clone(there)
	slices.Reverse(back)
	line := append(slices.Clone(there), back[1:]...)
	f := newFinder(line)
	half := geo.CumulativeDistance(there)[len(there)-1]
	for _, p := range line {
		f.find(p)
	}
	if along, off := f.find(line[len(line)-1]); along < 2*half-1 || off > 1 {
		t.Errorf("end found at %.0f m (off %.1f), want %.0f", along, off, 2*half)
	}
	f = newFinder(line)
	for _, p := range there {
		f.find(p)
	}
	if along, _ := f.find(back[10]); along < half {
		t.Errorf("way back found at %.0f m, on the way there", along)
	}
}

// offset moves p by dx metres east and dy metres north.
func offset(p geo.Point, dx, dy float64) geo.Point {
	return geo.Point{Lon: p.Lon + dx/(metresPerDegree*math.Cos(p.Lat*math.Pi/180)), Lat: p.Lat + dy/metresPerDegree}
}
