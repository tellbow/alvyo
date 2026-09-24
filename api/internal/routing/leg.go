package routing

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"

	"github.com/tellbow/odysgeh/swiss/elevation"
	"github.com/tellbow/odysgeh/swiss/geo"
	"github.com/tellbow/odysgeh/swiss/sac"
	"github.com/tellbow/odysgeh/swiss/stats"
)

const (
	// maxVertexSpacing is the densification step (metres) for elevation
	// sampling and per-segment attributes.
	maxVertexSpacing = 20
	// minTrailRun (metres): shorter changes of trail category are treated as
	// matching noise at junctions and merged into the surrounding run.
	minTrailRun = 40
	// snapWarning (metres): warn when a click is far from the nearest path.
	snapWarning = 100
	// throughM (metres): a path this close to where the line was dragged
	// counts as the path meant.
	throughM = 100
)

// Profiles offered to users (GraphHopper profile names).
var Profiles = []string{"hike", "alpine"}

// ErrElevation means the elevation service failed; the leg can be retried.
var ErrElevation = errors.New("routing: elevation unavailable")

// Router computes legs.
type Router struct {
	GraphHopper *GraphHopper
	Elevation   elevation.Sampler
	Trails      *TrailMatcher
}

// LegRequest asks for the leg between two anchors.
type LegRequest struct {
	From, To geo.Point
	Profile  string // "hike" or "alpine"
	Straight bool   // straight line instead of following paths
	// Through is where the line was dragged onto another path: the leg
	// takes the path that passes closest to it.
	Through *geo.Point
}

// Leg is a computed leg with everything the planner displays.
type Leg struct {
	Coordinates      [][3]float64       `json:"coordinates" doc:"[lon, lat, elevation] per vertex, at most 20 m apart"`
	DistanceM        float64            `json:"distance_m"`
	AscentM          float64            `json:"ascent_m"`
	DescentM         float64            `json:"descent_m"`
	EleMinM          float64            `json:"ele_min_m"`
	EleMaxM          float64            `json:"ele_max_m"`
	DurationS        int                `json:"duration_s" doc:"Swiss hiking time, start to end"`
	DurationReverseS int                `json:"duration_reverse_s" doc:"Swiss hiking time, end to start"`
	SAC              SACSummary         `json:"sac"`
	Surfaces         map[string]float64 `json:"surfaces" doc:"Metres per surface class: paved, gravel, natural, unknown"`
	WayTypes         map[string]float64 `json:"way_types" doc:"Metres per way type: road, track, path, steps, unknown"`
	Trails           map[string]float64 `json:"trails" doc:"Metres per official trail category"`
	Details          Details            `json:"details"`
	Snap             Snap               `json:"snap"`
	Warnings         []string           `json:"warnings" doc:"e.g. snap_far_from, snap_far_to"`
}

// SACSummary is the SAC grade of a leg.
type SACSummary struct {
	Grade       int                `json:"grade" doc:"Hardest segment, 1–6 for T1–T6"`
	Max         int                `json:"max" doc:"Upper end when the hardest part is only known as a range"`
	Breakdown   map[string]float64 `json:"breakdown" doc:"Metres per grade, keys T1–T6"`
	UnofficialM float64            `json:"unofficial_m" doc:"Metres graded by guess (off the official network, no OSM sac_scale)"`
}

// Details are per-segment attributes as runs over vertex indices.
type Details struct {
	SAC     []Run `json:"sac"`
	Surface []Run `json:"surface"`
	WayType []Run `json:"way_type"`
	Trail   []Run `json:"trail"`
}

// Run says that the segments between vertices From and To have Value.
type Run struct {
	From  int    `json:"from"`
	To    int    `json:"to"`
	Value string `json:"value"`
}

// Snap reports how far the anchors were moved onto the path network.
type Snap struct {
	FromM float64 `json:"from_m"`
	ToM   float64 `json:"to_m"`
}

// segment holds the facts known about one densified segment.
type segment struct {
	length    float64
	osmSAC    int
	roadClass string
	surface   string
	trail     sac.Category
}

// Leg computes one leg.
func (r *Router) Leg(ctx context.Context, req LegRequest) (Leg, error) {
	pts := []geo.Point{req.From, req.To}
	details := map[string][]interval{}
	leg := Leg{Warnings: []string{}}
	if !req.Straight {
		var gh ghRoute
		var err error
		if req.Through != nil {
			gh, err = r.routeThrough(ctx, req)
		} else {
			gh, err = r.GraphHopper.route(ctx, req.From, req.To, req.Profile)
		}
		if err != nil {
			return Leg{}, err
		}
		pts, details = gh.Points, gh.Details
		if n := len(gh.Snapped); n >= 2 {
			leg.Snap = Snap{FromM: geo.Distance(req.From, gh.Snapped[0]), ToM: geo.Distance(req.To, gh.Snapped[n-1])}
		}
	}
	if len(pts) < 2 {
		return Leg{}, ErrNoConnection
	}

	dense, orig := geo.Densify(pts, maxVertexSpacing)
	ele, err := r.Elevation.Sample(ctx, dense)
	if err != nil {
		return Leg{}, fmt.Errorf("%w: %w", ErrElevation, err)
	}
	trails, err := r.Trails.Categories(ctx, dense)
	if err != nil {
		return Leg{}, err
	}

	segs := make([]segment, len(dense)-1)
	for i := range segs {
		segs[i] = segment{length: geo.Distance(dense[i], dense[i+1]), trail: trails[i]}
	}
	applyDetails(segs, orig, details)
	smoothTrails(segs)
	finish(&leg, dense, ele, segs)

	if leg.Snap.FromM > snapWarning {
		leg.Warnings = append(leg.Warnings, "snap_far_from")
	}
	if leg.Snap.ToM > snapWarning {
		leg.Warnings = append(leg.Warnings, "snap_far_to")
	}
	return leg, nil
}

// routeThrough takes the one of GraphHopper's alternatives that passes
// closest to req.Through, if one comes within throughM; otherwise the path
// through the point itself, which then shapes the leg.
func (r *Router) routeThrough(ctx context.Context, req LegRequest) (ghRoute, error) {
	alts, err := r.GraphHopper.routes(ctx, []geo.Point{req.From, req.To}, req.Profile, true)
	if err != nil {
		return ghRoute{}, err
	}
	best, bestM := 0, math.Inf(1)
	for i, a := range alts {
		if len(a.Points) == 0 {
			continue
		}
		f := newFinder(a.Points)
		if _, off := f.find(*req.Through); off < bestM {
			best, bestM = i, off
		}
	}
	if bestM <= throughM {
		return alts[best], nil
	}
	via, err := r.GraphHopper.routes(ctx, []geo.Point{req.From, *req.Through, req.To}, req.Profile, false)
	if err != nil {
		return ghRoute{}, err
	}
	return via[0], nil
}

// Track computes legs along a given line, e.g. an imported GPS track,
// instead of routing, split into legs of about splitM metres so that later
// edits re-route only a part. Elevation, trail categories and statistics are
// computed as for planned legs; without OSM data, SAC grades come from the
// official trail categories.
func (r *Router) Track(ctx context.Context, pts []geo.Point, splitM float64) ([]Leg, error) {
	if len(pts) < 2 {
		return nil, ErrNoConnection
	}
	dense, _ := geo.Densify(pts, maxVertexSpacing)
	ele, err := r.Elevation.Sample(ctx, dense)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", ErrElevation, err)
	}
	trails, err := r.Trails.Categories(ctx, dense)
	if err != nil {
		return nil, err
	}
	segs := make([]segment, len(dense)-1)
	for i := range segs {
		segs[i] = segment{length: geo.Distance(dense[i], dense[i+1]), trail: trails[i]}
	}
	smoothTrails(segs)

	// Cut at segment boundaries every splitM metres; a short rest joins the
	// last leg.
	cuts := []int{0}
	acc := 0.0
	for i, sg := range segs {
		acc += sg.length
		if acc >= splitM && len(segs)-(i+1) > 0 {
			cuts = append(cuts, i+1)
			acc = 0
		}
	}
	if n := len(cuts); n > 1 && acc < splitM/4 {
		cuts = cuts[:n-1]
	}
	cuts = append(cuts, len(segs))
	legs := make([]Leg, 0, len(cuts)-1)
	for k := 0; k+1 < len(cuts); k++ {
		a, b := cuts[k], cuts[k+1]
		leg := Leg{Warnings: []string{}}
		finish(&leg, dense[a:b+1], ele[a:b+1], segs[a:b])
		legs = append(legs, leg)
	}
	return legs, nil
}

// finish fills a leg's line, statistics and summaries from its densified
// points, their elevations and segment facts.
func finish(leg *Leg, dense []geo.Point, ele []float64, segs []segment) {
	st := stats.Compute(dense, ele)
	leg.DistanceM = st.DistanceM
	leg.AscentM = math.Round(st.AscentM)
	leg.DescentM = math.Round(st.DescentM)
	leg.EleMinM = st.EleMinM
	leg.EleMaxM = st.EleMaxM
	leg.DurationS = int(st.Duration.Seconds())
	leg.DurationReverseS = int(st.DurationReverse.Seconds())

	leg.Coordinates = make([][3]float64, len(dense))
	for i, p := range dense {
		leg.Coordinates[i] = [3]float64{round6(p.Lon), round6(p.Lat), math.Round(ele[i]*10) / 10}
	}
	summarise(leg, segs)
}

// applyDetails spreads GraphHopper details (on original vertices) over the
// densified segments.
func applyDetails(segs []segment, orig []int, details map[string][]interval) {
	for key, list := range details {
		for _, iv := range list {
			if iv.From < 0 || iv.To >= len(orig) {
				continue
			}
			for k := orig[iv.From]; k < orig[iv.To] && k < len(segs); k++ {
				switch key {
				case "hike_rating":
					segs[k].osmSAC, _ = strconv.Atoi(iv.Value)
				case "road_class":
					segs[k].roadClass = iv.Value
				case "surface":
					segs[k].surface = iv.Value
				}
			}
		}
	}
}

// smoothTrails merges trail-category runs shorter than minTrailRun into the
// preceding run (or the following one at the start).
func smoothTrails(segs []segment) {
	type run struct {
		start, end int // segment indices, end exclusive
		length     float64
	}
	var runs []run
	for i := 0; i < len(segs); {
		j, l := i, 0.0
		for j < len(segs) && segs[j].trail == segs[i].trail {
			l += segs[j].length
			j++
		}
		runs = append(runs, run{i, j, l})
		i = j
	}
	for ri, rn := range runs {
		if rn.length >= minTrailRun || len(runs) == 1 {
			continue
		}
		var cat sac.Category
		if ri > 0 {
			cat = segs[runs[ri-1].start].trail
		} else {
			cat = segs[runs[ri+1].start].trail
		}
		for k := rn.start; k < rn.end; k++ {
			segs[k].trail = cat
		}
	}
}

func summarise(leg *Leg, segs []segment) {
	leg.Surfaces = map[string]float64{}
	leg.WayTypes = map[string]float64{}
	leg.Trails = map[string]float64{}

	sacSegs := make([]sac.Segment, len(segs))
	sacRuns := make([]string, len(segs))
	surfRuns := make([]string, len(segs))
	wayRuns := make([]string, len(segs))
	trailRuns := make([]string, len(segs))
	for i, s := range segs {
		sacSegs[i] = sac.Segment{LengthM: s.length, OSM: s.osmSAC, Category: s.trail, Path: isPath(s.roadClass)}
		sacRuns[i] = "T" + strconv.Itoa(sac.Of(sacSegs[i]).T)
		surfRuns[i] = surfaceGroup(s.surface)
		wayRuns[i] = wayType(s.roadClass)
		trailRuns[i] = s.trail.String()
		leg.Surfaces[surfRuns[i]] += s.length
		leg.WayTypes[wayRuns[i]] += s.length
		leg.Trails[trailRuns[i]] += s.length
	}
	roundValues(leg.Surfaces)
	roundValues(leg.WayTypes)
	roundValues(leg.Trails)

	sum := sac.Route(sacSegs)
	leg.SAC = SACSummary{Grade: sum.Grade, Max: sum.Max, Breakdown: map[string]float64{}, UnofficialM: math.Round(sum.UnofficialM)}
	for t, m := range sum.Breakdown {
		leg.SAC.Breakdown["T"+strconv.Itoa(t)] = math.Round(m)
	}
	leg.Details = Details{SAC: runs(sacRuns), Surface: runs(surfRuns), WayType: runs(wayRuns), Trail: runs(trailRuns)}
}

// runs compresses per-segment values into runs over vertex indices.
func runs(values []string) []Run {
	var out []Run
	for i, v := range values {
		if n := len(out); n > 0 && out[n-1].Value == v {
			out[n-1].To = i + 1
			continue
		}
		out = append(out, Run{From: i, To: i + 1, Value: v})
	}
	return out
}

func roundValues(m map[string]float64) {
	for k, v := range m {
		m[k] = math.Round(v)
	}
}

func round6(x float64) float64 { return math.Round(x*1e6) / 1e6 }
