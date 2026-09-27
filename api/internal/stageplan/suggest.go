package stageplan

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"math"
	"slices"

	"golang.org/x/sync/errgroup"

	"github.com/tellbow/alvyo/api/internal/places"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
)

// GraphHopper's alternatives stay in one valley (Thun–Zermatt: four of five
// over the Lötschenpass, none over the Gemmi), so other ways are found by
// making the way pass a village or hut to the side of the straight line.
// Points on the map instead land on peaks and glaciers.
var (
	// alongs are where along the straight line, sides how far to its side
	// (both as a share of its length) a place to pass is looked for.
	alongs = []float64{0.2, 0.35, 0.5, 0.65, 0.8}
	sides  = []float64{-0.4, -0.25, -0.12, 0.12, 0.25, 0.4}
)

const (
	maxSuggestions = 4
	// maxLonger: a way at most this much longer than the shortest.
	maxLonger = 1.5
	// maxOverlap: a way sharing more of its length than this with another is
	// the same. Ways between two places often share the valleys at both ends
	// (Thun–Kandersteg and Visp–Zermatt).
	maxOverlap = 0.75
	// passM: the place to pass is at most this far from where it is looked for.
	passM = 5000
	// sampleM: ways are compared at points this far apart; points of two
	// ways within sameWayM are on the same way.
	sampleM  = 200
	sameWayM = 300
	// A way that goes the same path back (up a dead-end valley to the point
	// and down again) for more than spurShare of its length is no way.
	spurShare  = 0.1
	spurM      = 100
	spurAlongM = 2000
)

// Suggestion is one way from start to destination, split into days.
type Suggestion struct {
	// Points are the points asked for, with the one the way passes; for
	// POST /journeys/plan, to move the nights of this way.
	Points []geo.Point
	// Via is the place the way passes, to tell the ways apart; empty for
	// the direct one.
	Via      string
	Proposal Proposal
}

// Suggest proposes up to four ways that differ, each split into days. Ways
// through the same village share the night there, where the hiker can
// change from one way to another. With req.Strict, ways with a day over
// the most are left out; if all are, a TooLongError with the fewest days
// of any.
func (p *Planner) Suggest(ctx context.Context, req Request) ([]Suggestion, error) {
	ways, err := p.ways(ctx, req)
	if err != nil {
		return nil, err
	}
	// Computed in full all at once: most of the time is elevation.
	legs := make([][]routing.Leg, len(ways))
	g, gctx := errgroup.WithContext(ctx)
	for i, w := range ways {
		g.Go(func() error {
			for k := 1; k < len(w.points); k++ {
				// The place passed is on the line as GraphHopper routed it.
				onPath := w.via > 0 && (k == w.via || k-1 == w.via)
				l, err := p.Router.Leg(gctx, routing.LegRequest{From: w.points[k-1], To: w.points[k], Profile: req.Profile, OnPath: onPath})
				if err != nil {
					return err
				}
				legs[i] = append(legs[i], l)
			}
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return nil, err
	}
	// Split one after the other, each favouring the nights of those before.
	favour := map[string]bool{}
	out := make([]Suggestion, 0, len(ways))
	var tooLong *TooLongError
	for i, w := range ways {
		r := req
		r.Ends, r.favour = nil, favour
		prop, err := p.Split(ctx, legs[i], r)
		if tl := (*TooLongError)(nil); errors.As(err, &tl) {
			if tooLong == nil || tl.Days > 0 && (tooLong.Days == 0 || tl.Days < tooLong.Days) {
				tooLong = tl
			}
			continue
		}
		if err != nil {
			return nil, err
		}
		for _, st := range prop.Stages {
			if st.EndPlace != nil {
				favour[st.EndPlace.ID] = true
			}
		}
		out = append(out, Suggestion{Points: w.points, Via: w.viaName, Proposal: prop})
	}
	if len(out) == 0 && tooLong != nil {
		return nil, tooLong
	}
	return out, nil
}

// way is a candidate way: the points it is routed through, and its line
// sampled every sampleM.
type way struct {
	points  []geo.Point
	via     int // index of the place passed in points; 0: none
	viaName string
	line    []geo.Point
	lengthM float64
}

func newWay(points, line []geo.Point) way {
	cum := geo.CumulativeDistance(line)
	return way{points: points, line: sample(line, sampleM), lengthM: cum[len(cum)-1]}
}

// ways finds the direct way and up to three others that differ from it and
// from each other, shortest first. They vary on the longest part between
// the points asked for.
func (p *Planner) ways(ctx context.Context, req Request) ([]way, error) {
	gh := p.Router.GraphHopper
	line, _, err := gh.Path(ctx, req.Points, req.Profile)
	if err != nil {
		return nil, err
	}
	if len(line) < 2 {
		return nil, routing.ErrNoConnection
	}
	direct := newWay(req.Points, line)

	k := 0
	for i := 1; i+1 < len(req.Points); i++ {
		if geo.Distance(req.Points[i], req.Points[i+1]) > geo.Distance(req.Points[k], req.Points[k+1]) {
			k = i
		}
	}
	targets, err := p.passes(ctx, sidePoints(req.Points[k], req.Points[k+1]))
	if err != nil {
		return nil, err
	}
	cands := make([]*way, len(targets))
	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(6)
	for i, t := range targets {
		g.Go(func() error {
			pts := slices.Insert(slices.Clone(req.Points), k+1, at(t.At))
			line, snapped, err := gh.Path(gctx, pts, req.Profile)
			if errors.Is(err, routing.ErrPointNotFound) || errors.Is(err, routing.ErrOutOfBounds) ||
				errors.Is(err, routing.ErrNoConnection) {
				return nil // no path near the point, or none over it: another will do
			}
			if err != nil {
				return err
			}
			if len(line) < 2 || len(snapped) != len(pts) {
				return nil
			}
			// Passing the point on the path: routed leg by leg, the way
			// is the same.
			pts[k+1] = snapped[k+1]
			w := newWay(pts, line)
			w.via, w.viaName = k+1, t.Name
			cands[i] = &w
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return nil, err
	}
	return pick(direct, cands), nil
}

// pick keeps the direct way and then, one at a time, the candidate with
// the most of its own (not on a way kept) for how much longer it is, among
// those not much longer, without a dead end, and with enough of their own.
// The ways come out shortest first.
func pick(direct way, cands []*way) []way {
	var ok []way
	for _, c := range cands {
		if c != nil && c.lengthM <= maxLonger*direct.lengthM && !spur(c.line) {
			ok = append(ok, *c)
		}
	}
	kept := []way{direct}
	for len(kept) < maxSuggestions {
		best, bestScore := -1, math.Inf(-1)
		for i, c := range ok {
			shared := 0.0
			for _, w := range kept {
				shared = max(shared, overlap(c.line, w.line))
			}
			if shared > maxOverlap {
				continue
			}
			if score := (1 - shared) - (c.lengthM/direct.lengthM - 1); score > bestScore {
				best, bestScore = i, score
			}
		}
		if best < 0 {
			break
		}
		kept = append(kept, ok[best])
		ok = slices.Delete(ok, best, best+1)
	}
	slices.SortStableFunc(kept, func(a, b way) int { return cmp.Compare(a.lengthM, b.lengthM) })
	return kept
}

// passes are the stops and huts nearest to the points, each once; points
// without one within passM have none.
func (p *Planner) passes(ctx context.Context, pts []geo.Point) ([]places.Place, error) {
	lons, lats := make([]float64, len(pts)), make([]float64, len(pts))
	for i, pt := range pts {
		lons[i], lats[i] = pt.Lon, pt.Lat
	}
	rows, err := p.DB.Query(ctx, `
		SELECT DISTINCT pl.id, pl.name, ST_X(pl.geom), ST_Y(pl.geom)
		FROM unnest($1::float8[], $2::float8[]) AS t(lon, lat)
		CROSS JOIN LATERAL (
			SELECT id, name, geom FROM places
			WHERE kind IN ('pt_stop', 'hut')
				AND ST_DWithin(geom::geography, ST_Point(t.lon, t.lat, 4326)::geography, $3)
			ORDER BY geom <-> ST_Point(t.lon, t.lat, 4326) LIMIT 1
		) pl
		ORDER BY pl.id`, lons, lats, passM)
	if err != nil {
		return nil, fmt.Errorf("stageplan: passes: %w", err)
	}
	defer rows.Close()
	var out []places.Place
	for rows.Next() {
		var pl places.Place
		if err := rows.Scan(&pl.ID, &pl.Name, &pl.At[0], &pl.At[1]); err != nil {
			return nil, err
		}
		out = append(out, pl)
	}
	return out, rows.Err()
}

// sidePoints are the points to pass, around the straight line from a to b.
func sidePoints(a, b geo.Point) []geo.Point {
	// Metres east and north of a, flat: enough at this scale.
	mx := math.Cos(a.Lat*math.Pi/180) * 111320
	const my = 110540
	dx, dy := (b.Lon-a.Lon)*mx, (b.Lat-a.Lat)*my
	var out []geo.Point
	for _, f := range alongs {
		for _, s := range sides {
			x, y := f*dx-s*dy, f*dy+s*dx // s to the left of a→b
			out = append(out, geo.Point{Lon: a.Lon + x/mx, Lat: a.Lat + y/my})
		}
	}
	return out
}

// overlap is the share of the points of a within sameWayM of b.
func overlap(a, b []geo.Point) float64 {
	g := newGrid(b, sameWayM)
	n := 0
	for _, p := range a {
		if g.any(p, sameWayM, func(int) bool { return true }) {
			n++
		}
	}
	return float64(n) / float64(len(a))
}

// spur tells whether the line comes back along itself for more than
// spurShare of its points.
func spur(line []geo.Point) bool {
	g := newGrid(line, spurM)
	n := 0
	for i, p := range line {
		// Only points far along the line: switchbacks are close too.
		if g.any(p, spurM, func(j int) bool { return abs(i-j)*sampleM >= spurAlongM }) {
			n++
		}
	}
	return float64(n) > spurShare*float64(len(line))
}

// grid finds the points near a point without measuring to all of them.
type grid struct {
	pts   []geo.Point
	cells map[[2]int][]int
	size  float64
}

func newGrid(pts []geo.Point, size float64) grid {
	g := grid{pts: pts, cells: map[[2]int][]int{}, size: size}
	for i, p := range pts {
		c := g.cell(p)
		g.cells[c] = append(g.cells[c], i)
	}
	return g
}

// cell is the square of side size the point is in; metres at Swiss
// latitudes, exact enough for cells.
func (g grid) cell(p geo.Point) [2]int {
	return [2]int{int(math.Floor(p.Lon * 76000 / g.size)), int(math.Floor(p.Lat * 111000 / g.size))}
}

// any tells whether a point within d (at most size) of p satisfies ok.
func (g grid) any(p geo.Point, d float64, ok func(i int) bool) bool {
	c := g.cell(p)
	for dx := -1; dx <= 1; dx++ {
		for dy := -1; dy <= 1; dy++ {
			for _, i := range g.cells[[2]int{c[0] + dx, c[1] + dy}] {
				if ok(i) && geo.Distance(p, g.pts[i]) <= d {
					return true
				}
			}
		}
	}
	return false
}

// sample keeps points at least step metres apart, and the last one.
func sample(line []geo.Point, step float64) []geo.Point {
	out := []geo.Point{line[0]}
	for _, p := range line[1 : len(line)-1] {
		if geo.Distance(out[len(out)-1], p) >= step {
			out = append(out, p)
		}
	}
	return append(out, line[len(line)-1])
}
