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

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/hikingtime"
)

func TestReach(t *testing.T) {
	var asked map[string][]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r.URL.Query()
		var polys []string
		for b := range 4 {
			x := float64(b + 1)
			polys = append(polys, fmt.Sprintf(
				`{"type":"Feature","properties":{"bucket":%d},"geometry":{"type":"Polygon","coordinates":[[[9.4,47.0],[%.7f,47.0],[9.4,47.123456789],[9.4,47.0]]]}}`,
				b, 9.4+x/10))
		}
		_, _ = fmt.Fprintf(w, `{"polygons":[%s],"info":{"took":5}}`, strings.Join(polys, ","))
	}))
	defer srv.Close()
	g := &GraphHopper{URL: srv.URL}

	areas, err := g.Reach(context.Background(), geo.Point{Lon: 9.4466, Lat: 47.0446}, "hike", 1.2)
	if err != nil {
		t.Fatal(err)
	}
	if asked["profile"][0] != "hike_time" || asked["point"][0] != "47.044600,9.446600" || asked["buckets"][0] != "4" {
		t.Errorf("asked %v", asked)
	}
	// Eight hours at a pace 1.2 times the signposts' are 6 h 40 of Swiss time.
	if asked["time_limit"][0] != "24000" {
		t.Errorf("time_limit %v", asked["time_limit"])
	}
	if len(areas) != 3 || areas[0].Hours != 2 || areas[1].Hours != 4 || areas[2].Hours != 8 {
		t.Fatalf("areas %+v", areas)
	}
	// Two hours: bucket 0; eight: bucket 3; rounded to 5 decimals.
	if areas[0].Outline[0][1][0] != 9.5 || areas[2].Outline[0][1][0] != 9.8 || areas[0].Outline[0][2][1] != 47.12346 {
		t.Errorf("outlines %v %v", areas[0].Outline, areas[2].Outline)
	}
}

func TestReachNoPath(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"message":"Point not found:47.1,9.2","hints":[{"message":"Point not found:47.1,9.2","details":"com.graphhopper.util.exceptions.PointNotFoundException"}]}`))
	}))
	defer srv.Close()
	_, err := (&GraphHopper{URL: srv.URL}).Reach(context.Background(), geo.Point{Lon: 9.2, Lat: 47.1}, "alpine", 1)
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
