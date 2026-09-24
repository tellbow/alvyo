package stageplan

import (
	"context"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/odysgeh/api/internal/places"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/swiss/geo"
)

const (
	// nearM: places this close to the line are where a day can end.
	nearM = 1000
	// onLineM: a place this close needs no leg of its own to reach it.
	onLineM = 30
	// bucketM: of the places of one kind along this much of the line, only
	// the nearest to it is considered (villages have many stops).
	bucketM = 250
	// legM: stage routes are cut into legs of this length, to edit in parts.
	legM = 2000
	// detourFactor: paths to a place are longer than the straight line.
	detourFactor = 1.3
	// flatSecondsPerM is the Swiss hiking time on flat ground.
	flatSecondsPerM = 14.271 * 60 / 1000
)

// ErrUnknownEnd means a place asked to end a day at is not near the line.
var ErrUnknownEnd = errors.New("stageplan: a chosen place is not along the route")

// Planner proposes the stages of a multi-day hike.
type Planner struct {
	Router *routing.Router
	DB     *pgxpool.Pool
}

// Request asks for a multi-day hike.
type Request struct {
	Points  []geo.Point // start, points to pass, destination
	Profile string      // hike or alpine
	Days    Days
	Kinds   []string // kinds of places preferred for the nights; none: all
	// Ends are place ids to end the days at, in order, instead of choosing
	// (from an earlier proposal's alternatives).
	Ends []string
}

// Stage is a proposed day.
type Stage struct {
	StartPlace    *places.Place `json:"start_place" doc:"Where the previous day ended; none on the first"`
	EndPlace      *places.Place `json:"end_place" doc:"Where the day ends; none on the last"`
	Accommodation string        `json:"accommodation" doc:"The hut, hotel or campsite; empty at a stop"`
	Totals        routes.Totals `json:"totals"`
	OverMax       bool          `json:"over_max" doc:"Longer than the maximum per day: there was no place to end it earlier"`
	// Earlier and Later are the places nearest before and after the end
	// place, to end the day there instead.
	Earlier *places.Place `json:"earlier"`
	Later   *places.Place `json:"later"`
	// The stage route, ready to save.
	Profile string          `json:"profile"`
	Anchors []routes.Anchor `json:"anchors"`
	Legs    []routing.Leg   `json:"legs"`
}

// Proposal is a multi-day hike split into stages.
type Proposal struct {
	Stages []Stage `json:"stages"`
	// Hiking time per day aimed at and the most per day, in seconds.
	TargetS int `json:"target_s"`
	MaxS    int `json:"max_s"`
}

// place is a place near the line.
type place struct {
	places.Place
	index   int     // nearest vertex
	offM    float64 // distance from it
	detourS float64
}

// Plan routes the whole way and splits it into days.
func (p *Planner) Plan(ctx context.Context, req Request) (Proposal, error) {
	var legs []routing.Leg
	for i := 1; i < len(req.Points); i++ {
		l, err := p.Router.Leg(ctx, routing.LegRequest{From: req.Points[i-1], To: req.Points[i], Profile: req.Profile})
		if err != nil {
			return Proposal{}, err
		}
		legs = append(legs, l)
	}
	return p.Split(ctx, legs, req)
}

// Split splits a line given as legs (routed, or an imported track) into
// days; req.Points are not used.
func (p *Planner) Split(ctx context.Context, legs []routing.Leg, req Request) (Proposal, error) {
	tr := FromLegs(legs)
	secs := tr.Seconds()
	near, err := p.near(ctx, tr)
	if err != nil {
		return Proposal{}, err
	}
	preferred := func(pl place) bool { return len(req.Kinds) == 0 || slices.Contains(req.Kinds, pl.Kind) }

	var ends []place
	if len(req.Ends) > 0 {
		for _, id := range req.Ends {
			i := slices.IndexFunc(near, func(pl place) bool { return pl.ID == id })
			if i < 0 || (len(ends) > 0 && near[i].index <= ends[len(ends)-1].index) {
				return Proposal{}, ErrUnknownEnd
			}
			ends = append(ends, near[i])
		}
	} else {
		cands := make([]Candidate, len(near))
		for i, pl := range near {
			cands[i] = Candidate{Index: pl.index, DetourS: pl.detourS, Preferred: preferred(pl)}
		}
		picked, err := Split(secs, cands, req.Days)
		if err != nil {
			return Proposal{}, err
		}
		for _, i := range picked {
			ends = append(ends, near[i])
		}
	}

	out := Proposal{}
	target := req.Days.TargetS
	if req.Days.N > 0 {
		target = secs[len(secs)-1] / float64(req.Days.N)
	}
	maxS := req.Days.MaxS
	if maxS <= 0 {
		maxS = math.Max(1.25*target, target+3600)
	}
	out.TargetS, out.MaxS = int(target), int(maxS)

	for k := 0; k <= len(ends); k++ {
		var from, to *place
		a, b := 0, len(tr.Coords)-1
		if k > 0 {
			from = &ends[k-1]
			a = from.index
		}
		if k < len(ends) {
			to = &ends[k]
			b = to.index
		}
		st, err := p.stage(ctx, tr, a, b, from, to, req.Profile)
		if err != nil {
			return Proposal{}, err
		}
		st.OverMax = float64(st.Totals.DurationS) > maxS
		if to != nil {
			lo, hi := a, len(tr.Coords)-1
			if k+1 < len(ends) {
				hi = ends[k+1].index
			}
			st.Earlier, st.Later = neighbours(near, to, lo, hi, preferred)
		}
		out.Stages = append(out.Stages, st)
	}
	return out, nil
}

// dayEndM: a place this close to where a recorded day ends is where the
// hiker probably slept.
const dayEndM = 400

// ByDay makes a stage of each day's legs, e.g. the days of a recording,
// ending at the nearest place, if one is close.
func (p *Planner) ByDay(ctx context.Context, days [][]routing.Leg, profile string) (Proposal, error) {
	var all []routing.Leg
	for _, d := range days {
		all = append(all, d...)
	}
	tr := FromLegs(all)
	near, err := p.near(ctx, tr)
	if err != nil {
		return Proposal{}, err
	}
	out := Proposal{}
	var from *place
	a, n := 0, 0
	for k, d := range days {
		size := len(FromLegs(d).Coords)
		if k > 0 {
			// A day that starts where the last ended shares its vertex;
			// otherwise it starts at the next one.
			if geo.Distance(point(tr.Coords[a]), point(d[0].Coordinates[0])) < jointM {
				size--
			} else {
				a++
			}
		}
		n += size
		b := n - 1
		var to *place
		if k < len(days)-1 {
			end := point(tr.Coords[b])
			for i := range near {
				d := geo.Distance(end, at(near[i].At))
				if d <= dayEndM && (to == nil || d < geo.Distance(end, at(to.At))) {
					pl := near[i]
					pl.offM = 0 // slept there: no way to it is added
					to = &pl
				}
			}
		}
		st, err := p.stage(ctx, tr, a, b, from, to, profile)
		if err != nil {
			return Proposal{}, err
		}
		out.Stages = append(out.Stages, st)
		from, a = to, b
	}
	return out, nil
}

// stage builds the day from vertex a to b, with the way from the previous
// night's place in the morning and to this night's in the evening.
func (p *Planner) stage(ctx context.Context, tr Track, a, b int, from, to *place, profile string) (Stage, error) {
	var legs []routing.Leg
	if from != nil && from.offM > onLineM {
		l, err := p.detour(ctx, at(from.At), point(tr.Coords[a]), profile)
		if err != nil {
			return Stage{}, err
		}
		legs = append(legs, l)
	}
	legs = append(legs, tr.Legs(a, b, legM)...)
	if to != nil && to.offM > onLineM {
		l, err := p.detour(ctx, point(tr.Coords[b]), at(to.At), profile)
		if err != nil {
			return Stage{}, err
		}
		legs = append(legs, l)
	}
	c := routes.Content{Profile: profile, Legs: legs}
	for _, l := range legs {
		c.Anchors = append(c.Anchors, routes.Anchor{Lon: l.Coordinates[0][0], Lat: l.Coordinates[0][1]})
	}
	last := legs[len(legs)-1].Coordinates
	c.Anchors = append(c.Anchors, routes.Anchor{Lon: last[len(last)-1][0], Lat: last[len(last)-1][1]})
	if from != nil {
		c.Anchors[0].Name = from.Name
	}
	if to != nil {
		c.Anchors[len(c.Anchors)-1].Name = to.Name
	}
	checked, totals, err := routes.Check(c)
	if err != nil {
		return Stage{}, fmt.Errorf("stageplan: stage: %w", err)
	}
	st := Stage{Profile: profile, Anchors: c.Anchors, Legs: checked, Totals: totals}
	if from != nil {
		st.StartPlace = &from.Place
	}
	if to != nil {
		st.EndPlace = &to.Place
		if to.Kind != "pt_stop" {
			st.Accommodation = to.Name
		}
	}
	return st, nil
}

// detour is the leg between the line and a place off it: along paths, or
// straight where there are none.
func (p *Planner) detour(ctx context.Context, from, to geo.Point, profile string) (routing.Leg, error) {
	req := routing.LegRequest{From: from, To: to, Profile: profile}
	l, err := p.Router.Leg(ctx, req)
	if errors.Is(err, routing.ErrPointNotFound) || errors.Is(err, routing.ErrNoConnection) {
		req.Straight = true
		l, err = p.Router.Leg(ctx, req)
	}
	return l, err
}

func at(lonLat [2]float64) geo.Point { return geo.Point{Lon: lonLat[0], Lat: lonLat[1]} }

// neighbours are the places nearest before and after end along the line,
// between the vertices lo and hi, of a preferred kind if there is one.
func neighbours(near []place, end *place, lo, hi int, preferred func(place) bool) (earlier, later *places.Place) {
	pick := func(ok func(place) bool, want func(pl place) bool, better func(a, b place) bool) *places.Place {
		var best *place
		for i := range near {
			pl := near[i]
			if pl.ID == end.ID || pl.index <= lo || pl.index >= hi || !want(pl) || !ok(pl) {
				continue
			}
			if best == nil || better(pl, *best) {
				best = &near[i]
			}
		}
		if best == nil {
			return nil
		}
		return &best.Place
	}
	before := func(pl place) bool { return pl.index < end.index }
	after := func(pl place) bool { return pl.index > end.index }
	closer := func(a, b place) bool { return abs(a.index-end.index) < abs(b.index-end.index) }
	anyKind := func(place) bool { return true }
	if earlier = pick(before, preferred, closer); earlier == nil {
		earlier = pick(before, anyKind, closer)
	}
	if later = pick(after, preferred, closer); later == nil {
		later = pick(after, anyKind, closer)
	}
	return earlier, later
}

func abs(x int) int { return max(x, -x) }

// near finds the places within nearM of the line, each at its nearest
// vertex, sorted along the line; per stretch of bucketM and kind only the
// nearest to the line.
func (p *Planner) near(ctx context.Context, tr Track) ([]place, error) {
	pts := tr.Points()
	var wkt strings.Builder
	wkt.WriteString("LINESTRING(")
	for i, pt := range pts {
		if i > 0 {
			wkt.WriteString(",")
		}
		fmt.Fprintf(&wkt, "%f %f", pt.Lon, pt.Lat)
	}
	wkt.WriteString(")")
	rows, err := p.DB.Query(ctx, `
		WITH line AS (SELECT ST_Simplify(ST_GeomFromText($1, 4326), 0.0001) AS g)
		SELECT p.id, p.kind, p.name, p.detail, CASE WHEN p.source = 'didok' THEN p.source_id ELSE '' END,
			p.website, ST_X(p.geom), ST_Y(p.geom)
		FROM places p, line
		WHERE ST_DWithin(p.geom::geography, line.g::geography, $2)`, wkt.String(), nearM)
	if err != nil {
		return nil, fmt.Errorf("stageplan: places: %w", err)
	}
	defer rows.Close()
	cum := geo.CumulativeDistance(pts)
	best := map[[2]any]place{}
	for rows.Next() {
		var pl place
		if err := rows.Scan(&pl.ID, &pl.Kind, &pl.Name, &pl.Detail, &pl.Ref, &pl.Website, &pl.At[0], &pl.At[1]); err != nil {
			return nil, err
		}
		here := at(pl.At)
		pl.offM = math.Inf(1)
		for i, v := range pts {
			if d := geo.Distance(here, v); d < pl.offM {
				pl.index, pl.offM = i, d
			}
		}
		pl.DistanceM = math.Round(pl.offM)
		pl.detourS = pl.offM * detourFactor * flatSecondsPerM
		key := [2]any{int(cum[pl.index] / bucketM), pl.Kind}
		if b, ok := best[key]; !ok || pl.offM < b.offM {
			best[key] = pl
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := make([]place, 0, len(best))
	for _, pl := range best {
		out = append(out, pl)
	}
	slices.SortFunc(out, func(a, b place) int {
		if a.index != b.index {
			return a.index - b.index
		}
		return strings.Compare(a.ID, b.ID)
	})
	return out, nil
}
