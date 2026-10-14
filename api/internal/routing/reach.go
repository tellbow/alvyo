package routing

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// ReachHours are the hours «Wie weit komme ich?» shows, each as an area.
var ReachHours = []int{2, 4, 8}

// ReachArea is what one reaches from a point within Hours: its outline, the
// outer ring first, [lon, lat] per point.
type ReachArea struct {
	Hours   int            `json:"hours"`
	Outline [][][2]float64 `json:"outline" doc:"Polygon rings, the outer one first; [lon, lat] per point"`
}

// reachTimeout: eight hours on foot search much of a region (about 10 s in
// production), more than a leg's 10 s.
const reachTimeout = 45 * time.Second

// Reach returns the areas reached from p within ReachHours at pace (one's
// time as a multiple of the Swiss hiking time), the smallest first.
// GraphHopper's isochrones over the time profiles (hike_time, alpine_time)
// time the ways by their slope like the Swiss formula.
func (g *GraphHopper) Reach(ctx context.Context, p geo.Point, profile string, pace float64) ([]ReachArea, error) {
	if pace <= 0 {
		pace = 1
	}
	most := ReachHours[len(ReachHours)-1]
	// Buckets of two hours: 2, 4, 6 and 8 h, of which 6 h is left out.
	const step = 2
	q := url.Values{
		"point":      {fmt.Sprintf("%.6f,%.6f", p.Lat, p.Lon)},
		"profile":    {profile + "_time"},
		"time_limit": {strconv.Itoa(int(math.Round(float64(most) * 3600 / pace)))},
		"buckets":    {strconv.Itoa(most / step)},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSuffix(g.URL, "/")+"/isochrone?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: reachTimeout}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("routing: graphhopper: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return nil, fmt.Errorf("routing: graphhopper: %w", err)
	}
	var r struct {
		ghResponse
		Polygons []struct {
			Properties struct {
				Bucket int `json:"bucket"`
			} `json:"properties"`
			Geometry struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"polygons"`
	}
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("routing: graphhopper returned %s: %w", resp.Status, err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, classifyError(resp.StatusCode, r.ghResponse)
	}
	var out []ReachArea
	for _, h := range ReachHours {
		for _, poly := range r.Polygons {
			if (poly.Properties.Bucket+1)*step != h {
				continue
			}
			a := ReachArea{Hours: h, Outline: make([][][2]float64, len(poly.Geometry.Coordinates))}
			for i, ring := range poly.Geometry.Coordinates {
				a.Outline[i] = make([][2]float64, len(ring))
				for j, c := range ring {
					// About 1 m: enough for an outline, a third of the bytes.
					a.Outline[i][j] = [2]float64{round5(c[0]), round5(c[1])}
				}
			}
			out = append(out, a)
		}
	}
	return out, nil
}

func round5(v float64) float64 { return math.Round(v*1e5) / 1e5 }
