package routing

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Turn is a junction where the route turns, for spoken navigation.
type Turn struct {
	AlongM float64 `json:"along_m" doc:"Metres from the start of the route"`
	Kind   string  `json:"kind" enum:"sharp_left,left,slight_left,keep_left,u_turn,slight_right,right,sharp_right,keep_right"`
}

// turnKinds maps GraphHopper instruction signs to turns; the other signs
// (continue, finish, roundabouts) are not turns.
var turnKinds = map[int]string{
	-98: "u_turn", -8: "u_turn", 8: "u_turn",
	-7: "keep_left", -3: "sharp_left", -2: "left", -1: "slight_left",
	1: "slight_right", 2: "right", 3: "sharp_right", 7: "keep_right",
}

const (
	// matchAccuracyM is GraphHopper's gps_accuracy for matching, and the
	// spacing of the points sent.
	matchAccuracyM = 20
	// onLineM (metres): the matched path this close to the line is the
	// line's own path.
	onLineM = 8
	// turnCheckM: the matched path this far before and after a turn must be
	// on the line, so that detours around parts off the network (a straight
	// leg, say) give no turns.
	turnCheckM = 30
	// onLineShare of the line's points this far around a turn (areaM) must
	// be on the matched path, where they are near it (nearM). GPS tracks miss
	// it: matching their jitter jumps between parallel ways and back, which
	// yields turns that are not there. Points far from the path, on a part
	// off the network, do not count.
	onLineShare = 0.9
	areaM       = 150
	nearM       = 30
	// sampleM is the step for comparing the matched path with the line.
	sampleM = 10
)

// Turns matches a line onto the path network and returns the turns along
// it, in order. Lines that do not follow the network get none.
func (g *GraphHopper) Turns(ctx context.Context, line []geo.Point) ([]Turn, error) {
	if len(line) < 2 {
		return []Turn{}, nil
	}
	path, turns, err := g.match(ctx, thin(line, matchAccuracyM))
	if err != nil || path == nil {
		return []Turn{}, err
	}
	return placeTurns(line, path, turns), nil
}

// matchedTurn is a turn at vertex At of the matched path.
type matchedTurn struct {
	At   int
	Kind string
}

// match returns the matched path and its turns, or no path when GraphHopper
// cannot match the line.
func (g *GraphHopper) match(ctx context.Context, pts []geo.Point) ([]geo.Point, []matchedTurn, error) {
	var gpx bytes.Buffer
	gpx.WriteString(`<?xml version="1.0"?><gpx version="1.1" creator="alvyo" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>`)
	for _, p := range pts {
		fmt.Fprintf(&gpx, `<trkpt lat="%.6f" lon="%.6f"/>`, p.Lat, p.Lon)
	}
	gpx.WriteString(`</trkseg></trk></gpx>`)
	// alpine: every path the hike profile allows, and the harder ones.
	url := fmt.Sprintf("%s/match?profile=alpine&gps_accuracy=%d&points_encoded=false&instructions=true",
		strings.TrimSuffix(g.URL, "/"), matchAccuracyM)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, &gpx)
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Content-Type", "application/gpx+xml")
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("routing: graphhopper: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return nil, nil, fmt.Errorf("routing: graphhopper: %w", err)
	}
	var r struct {
		Message string `json:"message"`
		Paths   []struct {
			Points struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"points"`
			Instructions []struct {
				Sign     int    `json:"sign"`
				Interval [2]int `json:"interval"`
			} `json:"instructions"`
		} `json:"paths"`
	}
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, nil, fmt.Errorf("routing: graphhopper returned %s: %w", resp.Status, err)
	}
	switch {
	case resp.StatusCode == http.StatusBadRequest:
		return nil, nil, nil // e.g. "Sequence is broken for submitted track"
	case resp.StatusCode != http.StatusOK || len(r.Paths) == 0:
		return nil, nil, fmt.Errorf("routing: graphhopper returned %d: %s", resp.StatusCode, r.Message)
	}
	p := r.Paths[0]
	path := make([]geo.Point, len(p.Points.Coordinates))
	for i, c := range p.Points.Coordinates {
		path[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	var turns []matchedTurn
	for _, in := range p.Instructions {
		if k, ok := turnKinds[in.Sign]; ok && in.Interval[0] < len(path) {
			turns = append(turns, matchedTurn{At: in.Interval[0], Kind: k})
		}
	}
	return path, turns, nil
}

// thin keeps points at least step metres apart, and the last one.
func thin(line []geo.Point, step float64) []geo.Point {
	out := []geo.Point{line[0]}
	for _, p := range line[1 : len(line)-1] {
		if geo.Distance(out[len(out)-1], p) >= step {
			out = append(out, p)
		}
	}
	return append(out, line[len(line)-1])
}

// placeTurns finds the matched path's turns on the line: it samples the path,
// finds each sample on the line, and keeps the turns where the path and the
// line around them are the same.
func placeTurns(line, path []geo.Point, turns []matchedTurn) []Turn {
	cum := geo.CumulativeDistance(path)
	var at []float64 // distances along the path to compare
	for d := 0.0; d < cum[len(cum)-1]; d += sampleM {
		at = append(at, d)
	}
	at = append(at, cum[len(cum)-1])
	for _, t := range turns {
		at = append(at, cum[t.At])
	}
	sort.Float64s(at)

	f := newFinder(line)
	along, off := make([]float64, len(at)), make([]float64, len(at))
	for i, d := range at {
		along[i], off[i] = f.find(pointAt(path, cum, d))
	}

	// And the line's own points on the path: a jittery line keeps crossing
	// the path, so the path's points all seem near the line; the line's
	// points show the jitter.
	lc := geo.CumulativeDistance(line)
	g := newFinder(path)
	lineOff := make([]float64, len(line))
	for i, p := range line {
		_, lineOff[i] = g.find(p)
	}

	out := []Turn{}
	for _, t := range turns {
		c := cum[t.At]
		k := sort.SearchFloat64s(at, c)
		ok := true
		for j := sort.SearchFloat64s(at, c-turnCheckM); j < len(at) && at[j] <= c+turnCheckM; j++ {
			ok = ok && off[j] <= onLineM
		}
		on, near := 0, 0
		for i := sort.SearchFloat64s(lc, along[k]-areaM); i < len(lc) && lc[i] <= along[k]+areaM; i++ {
			switch {
			case lineOff[i] <= onLineM:
				on++
			case lineOff[i] <= nearM:
				near++
			}
		}
		if ok && float64(on) >= onLineShare*float64(on+near) && (len(out) == 0 || along[k] >= out[len(out)-1].AlongM) {
			out = append(out, Turn{AlongM: math.Round(along[k]*10) / 10, Kind: t.Kind})
		}
	}
	return calm(out)
}

// jogM: turns this close that cancel out (right then left, or turning back
// twice) are a step to a parallel way, such as across a road, or matching
// noise; they are not announced.
const jogM = 15

// calm drops the turns that cancel out.
func calm(turns []Turn) []Turn {
	side := func(k string) string {
		switch {
		case strings.HasSuffix(k, "left"):
			return "left"
		case strings.HasSuffix(k, "right"):
			return "right"
		}
		return k
	}
	out := []Turn{}
	for _, t := range turns {
		if n := len(out); n > 0 && t.AlongM-out[n-1].AlongM <= jogM {
			a, b := side(out[n-1].Kind), side(t.Kind)
			if a == "left" && b == "right" || a == "right" && b == "left" || a == "u_turn" && b == "u_turn" {
				out = out[:n-1]
				continue
			}
		}
		out = append(out, t)
	}
	return out
}

// pointAt is the point d metres along a line with cumulative distances cum.
func pointAt(line []geo.Point, cum []float64, d float64) geo.Point {
	i := sort.SearchFloat64s(cum, d)
	if i == 0 {
		return line[0]
	}
	if i >= len(line) {
		return line[len(line)-1]
	}
	a, b := line[i-1], line[i]
	f := 0.0
	if s := cum[i] - cum[i-1]; s > 0 {
		f = (d - cum[i-1]) / s
	}
	return geo.Point{Lon: a.Lon + (b.Lon-a.Lon)*f, Lat: a.Lat + (b.Lat-a.Lat)*f}
}

// finder finds points on a line, in order: each search looks a little back
// and farther ahead of the last find, and prefers ahead, so that the way
// back of an out-and-back route is not taken for the way there.
type finder struct {
	xy   [][2]float64 // local metres
	cum  []float64
	kx   float64
	last float64 // along the line, of the last find
}

const findBackM, findAheadM = 50, 500

// metresPerDegree of latitude on the mean sphere.
const metresPerDegree = 6371008.8 * math.Pi / 180

func newFinder(line []geo.Point) *finder {
	f := &finder{cum: geo.CumulativeDistance(line), kx: metresPerDegree * math.Cos(line[0].Lat*math.Pi/180)}
	f.xy = make([][2]float64, len(line))
	for i, p := range line {
		f.xy[i] = [2]float64{p.Lon * f.kx, p.Lat * metresPerDegree}
	}
	return f
}

// find returns how far along the line p is found, and how far from it.
func (f *finder) find(p geo.Point) (alongM, offM float64) {
	q := [2]float64{p.Lon * f.kx, p.Lat * metresPerDegree}
	alongM, offM = f.search(q, f.last+findAheadM)
	if offM > nearM {
		// Lost, e.g. where one of the lines detours around a part off the
		// network: look all the way ahead.
		if a, o := f.search(q, math.Inf(1)); o < offM {
			alongM, offM = a, o
		}
	}
	f.last = alongM
	return alongM, offM
}

// search finds q on the line between a little behind the last find and to.
func (f *finder) search(q [2]float64, to float64) (alongM, offM float64) {
	if len(f.xy) == 1 {
		return 0, math.Hypot(q[0]-f.xy[0][0], q[1]-f.xy[0][1])
	}
	best := math.Inf(1)
	for i := max(sort.SearchFloat64s(f.cum, f.last-findBackM)-1, 0); i+1 < len(f.xy); i++ {
		if f.cum[i] > to {
			break
		}
		a, b := f.xy[i], f.xy[i+1]
		dx, dy := b[0]-a[0], b[1]-a[1]
		t := 0.0
		if l2 := dx*dx + dy*dy; l2 > 0 {
			t = math.Max(0, math.Min(1, ((q[0]-a[0])*dx+(q[1]-a[1])*dy)/l2))
		}
		d := math.Hypot(q[0]-(a[0]+t*dx), q[1]-(a[1]+t*dy))
		along := f.cum[i] + t*(f.cum[i+1]-f.cum[i])
		// Going back costs: on the way back of an out-and-back route, the
		// way there is just as near.
		if score := d + max(f.last-along, 0); score < best {
			best, alongM, offM = score, along, d
		}
	}
	return alongM, offM
}
