package routing

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/hikingtime"
)

// A path due east, a node every 0.005° (about 380 m), 10 minutes a node.
func TestReach(t *testing.T) {
	var asked *http.Request
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r
		var b strings.Builder
		b.WriteString("from_node,to_node,time,geometry\n-1,0,0,9.4 47.0\n")
		for i := 1; i <= 60; i++ {
			fmt.Fprintf(&b, "%d,%d,%d,%.3f 47.0;%.3f 47.0\n", i-1, i, i*10*60000, 9.4+float64(i-1)*0.005, 9.4+float64(i)*0.005)
		}
		_, _ = w.Write([]byte(b.String()))
	}))
	defer srv.Close()
	r := &Router{GraphHopper: &GraphHopper{URL: srv.URL}, Outlines: &Outliner{DB: testdb.New(t)}}

	areas, err := r.Reach(context.Background(), geo.Point{Lon: 9.4, Lat: 47.0}, "hike", 1.2)
	if err != nil {
		t.Fatal(err)
	}
	q := asked.URL.Query()
	// One tree, out from the point; eight hours at a pace 1.2 times the
	// signposts' are 6 h 40 of Swiss time, and 15 % beyond.
	if asked.URL.Path != "/reach-tree" || q.Get("profile") != "hike_time" || q.Get("point") != "47.000000,9.400000" ||
		q.Get("reverse_flow") != "false" || q.Get("time_limit") != "27600" {
		t.Errorf("asked %v", asked.URL)
	}
	if len(areas) != 3 || areas[0].Hours != 2 || areas[1].Hours != 4 || areas[2].Hours != 8 {
		t.Fatalf("areas %+v", areas)
	}
	east := func(a ReachArea) float64 {
		m := 0.0
		for _, p := range a.Outline[0] {
			m = max(m, p[0])
		}
		return m
	}
	// Two hours at pace 1.2: 10 nodes; eight hours: 40.
	if e := east(areas[0]); e < 9.45 || e > 9.45+2*cellLon {
		t.Errorf("2 h reach east to %.4f, want about 9.45", e)
	}
	if e := east(areas[2]); e < 9.60 || e > 9.60+2*cellLon {
		t.Errorf("8 h reach east to %.4f, want about 9.60", e)
	}
}

// A path with no junction for 0.05° (about 3.8 km, four hours): two hours
// reach halfway along it, not just its start.
func TestReachFrontier(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("from_node,to_node,time,geometry\n-1,0,0,9.4 47.0\n0,1,14400000,9.4 47.0;9.45 47.0\n"))
	}))
	defer srv.Close()
	r := &Router{GraphHopper: &GraphHopper{URL: srv.URL}, Outlines: &Outliner{DB: testdb.New(t)}}
	areas, err := r.Reach(context.Background(), geo.Point{Lon: 9.4, Lat: 47.0}, "hike", 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(areas) != 3 {
		t.Fatalf("areas %+v", areas)
	}
	for i, want := range []float64{9.425, 9.45} {
		e := 0.0
		for _, p := range areas[i].Outline[0] {
			e = max(e, p[0])
		}
		if e < want || e > want+2*cellLon {
			t.Errorf("%d h reach east to %.4f, want about %.3f", areas[i].Hours, e, want)
		}
	}
}

// Two paths from the start, an hour each, to nodes 1 (east) and 2 (north),
// joined by a path of two hours that bends far east: the tree never takes
// it, its ends are reached faster, but two hours reach halfway round it
// from each end, so along its bend.
func TestReachWays(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("from_node,to_node,time,geometry\n-1,0,0,9.4 47.0\n" +
			"0,1,3600000,9.4 47.0;9.45 47.0\n0,2,3600000,9.4 47.0;9.4 47.03\n" +
			"1,2,10800000,9.45 47.0;9.5 47.03;9.4 47.03\n2,1,10800000,9.4 47.03;9.5 47.03;9.45 47.0\n"))
	}))
	defer srv.Close()
	r := &Router{GraphHopper: &GraphHopper{URL: srv.URL}, Outlines: &Outliner{DB: testdb.New(t)}}
	areas, err := r.Reach(context.Background(), geo.Point{Lon: 9.4, Lat: 47.0}, "hike", 1)
	if err != nil {
		t.Fatal(err)
	}
	e := 0.0
	for _, p := range areas[0].Outline[0] {
		e = max(e, p[0])
	}
	if areas[0].Hours != 2 || e < 9.5 {
		t.Errorf("%d h reach east to %.4f, want the bend at 9.5", areas[0].Hours, e)
	}
}

func TestReachNoPath(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"message":"Point not found:47.1,9.2","hints":[{"message":"Point not found:47.1,9.2","details":"com.graphhopper.util.exceptions.PointNotFoundException"}]}`))
	}))
	defer srv.Close()
	_, err := (&Router{GraphHopper: &GraphHopper{URL: srv.URL}}).Reach(context.Background(), geo.Point{Lon: 9.2, Lat: 47.1}, "alpine", 1)
	if !errors.Is(err, ErrPointNotFound) {
		t.Fatalf("got %v", err)
	}
}

// The time models' speed per slope band is the Swiss formula's average over
// the band: what one walks there in an hour, horizontally. GraphHopper
// stores slopes up to 31 %; the steepest bands stand for paths up to 35 %.
func TestTimeModels(t *testing.T) {
	for _, name := range []string{"swiss_hike_time.json", "swiss_alpine_time.json"} {
		raw, err := os.ReadFile("../../../infra/graphhopper/custom_models/" + name)
		if err != nil {
			t.Fatal(err)
		}
		var model struct {
			Speed []map[string]string `json:"speed"`
		}
		comments := regexp.MustCompile(`(?m)^\s*//.*$|\s//[^"\n]*$`)
		if err := json.Unmarshal(comments.ReplaceAll(raw, nil), &model); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		cond := regexp.MustCompile(`^average_slope (>=|>) (-?\d+)$`)
		// The statement that applies at a stored slope.
		band := func(s int) int {
			s = max(-31, min(31, s))
			for i, st := range model.Speed {
				c := st["if"] + st["else_if"]
				if _, isElse := st["else"]; isElse && c == "" {
					return i
				}
				m := cond.FindStringSubmatch(c)
				if m == nil {
					t.Fatalf("%s: condition %q", name, c)
				}
				v, _ := strconv.Atoi(m[2])
				if (m[1] == ">=" && s >= v) || (m[1] == ">" && s > v) {
					return i
				}
			}
			t.Fatalf("%s: no statement for %d %%", name, s)
			return -1
		}
		minutes := map[int][]float64{}
		for s := -35; s <= 35; s++ {
			minutes[band(s)] = append(minutes[band(s)], hikingtime.MinutesPerKm(float64(s)/10))
		}
		for i, st := range model.Speed {
			sum := 0.0
			for _, m := range minutes[i] {
				sum += m
			}
			want := 60 / (sum / float64(len(minutes[i])))
			got, _ := strconv.ParseFloat(st["limit_to"], 64)
			if math.Abs(got-want) > 0.01 {
				t.Errorf("%s: statement %d (%v): %.2f km/h, the formula %.3f", name, i, st, got, want)
			}
		}
	}
}
