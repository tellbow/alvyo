// Package routing computes hiking legs: GraphHopper for the path, swissALTI3D
// for elevation, swissTLM3D for trail categories, and the Swiss domain rules
// (hiking time, SAC grade) for the numbers shown to users.
package routing

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Errors from the routing engine that callers map to user-facing messages.
var (
	ErrPointNotFound = errors.New("routing: no path near a point")
	ErrOutOfBounds   = errors.New("routing: point outside the covered area")
	ErrNoConnection  = errors.New("routing: no connection between the points")
)

// detailKeys are the GraphHopper path details requested for every leg.
var detailKeys = []string{"hike_rating", "foot_network", "surface", "road_class"}

// GraphHopper is a client for a GraphHopper server.
type GraphHopper struct {
	URL    string       // e.g. http://graphhopper:8989
	Client *http.Client // defaults to a 10 s timeout
}

// interval is a GraphHopper path detail: Value applies to the segments
// between vertices From and To.
type interval struct {
	From, To int
	Value    string
}

type ghRoute struct {
	Points  []geo.Point
	Snapped []geo.Point
	Details map[string][]interval
}

type ghResponse struct {
	Message string `json:"message"`
	// Hints is an array of error hints on failure but an object of
	// statistics on success, so it is decoded only for errors.
	Hints json.RawMessage `json:"hints"`
	Paths []struct {
		Points struct {
			Coordinates [][]float64 `json:"coordinates"`
		} `json:"points"`
		SnappedWaypoints struct {
			Coordinates [][]float64 `json:"coordinates"`
		} `json:"snapped_waypoints"`
		Details map[string][][3]any `json:"details"`
	} `json:"paths"`
}

func (g *GraphHopper) route(ctx context.Context, from, to geo.Point, profile string) (ghRoute, error) {
	rs, err := g.routes(ctx, []geo.Point{from, to}, profile, false)
	if err != nil {
		return ghRoute{}, err
	}
	return rs[0], nil
}

// routes returns the path through pts, or with alternatives the path between
// two points and up to four others.
func (g *GraphHopper) routes(ctx context.Context, pts []geo.Point, profile string, alternatives bool) ([]ghRoute, error) {
	points := make([][2]float64, len(pts))
	for i, p := range pts {
		points[i] = [2]float64{p.Lon, p.Lat}
	}
	params := map[string]any{
		"points":         points,
		"profile":        profile,
		"points_encoded": false,
		"instructions":   false,
		"details":        detailKeys,
	}
	if alternatives {
		// GraphHopper's defaults rarely find one on trails; paths up to twice
		// as long that share up to 80 % with the best one are wanted here.
		params["algorithm"] = "alternative_route"
		params["alternative_route.max_paths"] = 5
		params["alternative_route.max_weight_factor"] = 2
		params["alternative_route.max_share_factor"] = 0.8
	}
	body, _ := json.Marshal(params)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(g.URL, "/")+"/route", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
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
	var r ghResponse
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("routing: graphhopper returned %s: %w", resp.Status, err)
	}
	if resp.StatusCode != http.StatusOK || len(r.Paths) == 0 {
		return nil, classifyError(resp.StatusCode, r)
	}

	out := make([]ghRoute, len(r.Paths))
	for i, p := range r.Paths {
		o := ghRoute{Details: map[string][]interval{}}
		for _, c := range p.Points.Coordinates {
			o.Points = append(o.Points, geo.Point{Lon: c[0], Lat: c[1]})
		}
		for _, c := range p.SnappedWaypoints.Coordinates {
			o.Snapped = append(o.Snapped, geo.Point{Lon: c[0], Lat: c[1]})
		}
		for key, list := range p.Details {
			for _, d := range list {
				from, _ := d[0].(float64)
				to, _ := d[1].(float64)
				o.Details[key] = append(o.Details[key], interval{From: int(from), To: int(to), Value: detailValue(d[2])})
			}
		}
		out[i] = o
	}
	return out, nil
}

// detailValue normalises a detail value (number, string or null) to a string.
func detailValue(v any) string {
	switch x := v.(type) {
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case string:
		return x
	default:
		return ""
	}
}

func classifyError(status int, r ghResponse) error {
	var hints []struct {
		Details string `json:"details"`
	}
	_ = json.Unmarshal(r.Hints, &hints)
	for _, h := range hints {
		switch {
		case strings.HasSuffix(h.Details, "PointNotFoundException"):
			return ErrPointNotFound
		case strings.HasSuffix(h.Details, "PointOutOfBoundsException"):
			return ErrOutOfBounds
		case strings.HasSuffix(h.Details, "ConnectionNotFoundException"):
			return ErrNoConnection
		}
	}
	return fmt.Errorf("routing: graphhopper returned %d: %s", status, r.Message)
}
