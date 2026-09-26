package elevation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/lv95"
)

// GeoAdminURL is the swisstopo elevation profile service (swissALTI3D / DHM25).
const GeoAdminURL = "https://api3.geo.admin.ch/rest/services/profile.json"

// maxPoints is the service limit for both input coordinates and nb_points.
const maxPoints = 5000

// GeoAdmin samples heights from the geo.admin.ch profile service. It uses the
// COMB model: swissALTI3D (2 m) where available, DHM25 elsewhere.
type GeoAdmin struct {
	BaseURL   string       // defaults to GeoAdminURL
	Client    *http.Client // defaults to a client with a 20 s timeout
	UserAgent string

	chunkSize int // vertices per request; overridden in tests
}

type profilePoint struct {
	Dist float64 `json:"dist"`
	Alts struct {
		COMB  *float64 `json:"COMB"`
		DTM2  *float64 `json:"DTM2"`
		DTM25 *float64 `json:"DTM25"`
	} `json:"alts"`
}

// Sample implements Sampler.
func (g *GeoAdmin) Sample(ctx context.Context, pts []geo.Point) ([]float64, error) {
	if len(pts) == 0 {
		return nil, nil
	}
	chunk := g.chunkSize
	if chunk == 0 {
		chunk = 4000
	}

	out := make([]float64, len(pts))
	// Consecutive chunks share one vertex so every segment is inside a request.
	for start := 0; start < len(pts); start += chunk - 1 {
		end := min(start+chunk, len(pts))
		h, err := g.sampleChunk(ctx, pts[start:end])
		if err != nil {
			return nil, err
		}
		copy(out[start:end], h)
		if end == len(pts) {
			break
		}
	}
	return out, nil
}

// sampleChunk queries one request's worth of vertices. The service returns
// every input vertex (distinct_points) plus samples in between, keyed by
// planar LV95 distance, so heights are interpolated back by distance.
func (g *GeoAdmin) sampleChunk(ctx context.Context, pts []geo.Point) ([]float64, error) {
	coords := make([][2]float64, len(pts))
	dist := make([]float64, len(pts))
	for i, p := range pts {
		e, n := lv95.FromWGS84(p.Lon, p.Lat)
		coords[i] = [2]float64{math.Round(e*10) / 10, math.Round(n*10) / 10}
		if i > 0 {
			dist[i] = dist[i-1] + math.Hypot(coords[i][0]-coords[i-1][0], coords[i][1]-coords[i-1][1])
		}
	}
	if dist[len(dist)-1] == 0 {
		// One spot (a point, or points within 0.1 m): the service refuses a
		// line without length, so it is asked for one of 1 m from there.
		coords = [][2]float64{coords[0], {coords[0][0] + 1, coords[0][1]}}
	}

	profile, err := g.fetch(ctx, coords, max(len(coords), 2))
	if err != nil {
		return nil, err
	}

	var xs, ys []float64
	for _, p := range profile {
		if h := height(p); !math.IsNaN(h) {
			xs = append(xs, p.Dist)
			ys = append(ys, h)
		}
	}
	if len(xs) == 0 {
		return nil, ErrNoCoverage
	}
	// Missing heights inside the line are bridged by interpolation; the
	// service rounds distances to 0.1 m, which is well below sample spacing.
	return geo.Interpolate(xs, ys, dist), nil
}

func height(p profilePoint) float64 {
	for _, h := range []*float64{p.Alts.COMB, p.Alts.DTM2, p.Alts.DTM25} {
		if h != nil {
			return *h
		}
	}
	return math.NaN()
}

func (g *GeoAdmin) fetch(ctx context.Context, coords [][2]float64, nb int) ([]profilePoint, error) {
	body, err := json.Marshal(map[string]any{"type": "LineString", "coordinates": coords})
	if err != nil {
		return nil, err
	}
	base := g.BaseURL
	if base == "" {
		base = GeoAdminURL
	}
	q := url.Values{
		"sr":              {"2056"},
		"nb_points":       {strconv.Itoa(min(nb, maxPoints))},
		"distinct_points": {"true"},
	}
	u := base + "?" + q.Encode()

	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}

	var lastErr error
	for attempt := range 3 {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(attempt*attempt) * 300 * time.Millisecond):
			}
		}
		profile, retry, err := g.do(ctx, client, u, body)
		if err == nil || !retry {
			return profile, err
		}
		lastErr = err
	}
	return nil, lastErr
}

// do performs one request; retry reports whether the error is transient.
func (g *GeoAdmin) do(ctx context.Context, client *http.Client, u string, body []byte) (_ []profilePoint, retry bool, _ error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Content-Type", "application/json")
	if g.UserAgent != "" {
		req.Header.Set("User-Agent", g.UserAgent)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, ctx.Err() == nil, fmt.Errorf("elevation: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	// Any 2xx carries data: the service sometimes answers 203 (served from a
	// cache) with a normal body.
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		transient := resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500
		return nil, transient, fmt.Errorf("elevation: geo.admin returned %s: %s", resp.Status, bytes.TrimSpace(msg))
	}
	var profile []profilePoint
	if err := json.NewDecoder(resp.Body).Decode(&profile); err != nil {
		return nil, true, fmt.Errorf("elevation: decoding response: %w", err)
	}
	return profile, false, nil
}
