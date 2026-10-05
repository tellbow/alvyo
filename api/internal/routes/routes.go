package routes

import (
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
)

// Anchor is a point the user placed in the planner.
type Anchor struct {
	Lon      float64 `json:"lon" minimum:"5.7" maximum:"10.7"`
	Lat      float64 `json:"lat" minimum:"45.65" maximum:"47.95"`
	Straight bool    `json:"straight" required:"false" doc:"The leg arriving at this anchor is a straight line"`
	Alpine   bool    `json:"alpine,omitempty" required:"false" doc:"The leg arriving at this anchor uses the alpine profile on a hike route"`
	Name     string  `json:"name,omitempty" required:"false" maxLength:"120" doc:"The place it was found as by search"`
	Through  *LonLat `json:"through,omitempty" required:"false" doc:"The leg arriving at this anchor was dragged onto the path closest to this point"`
}

// LonLat is a position in the covered area.
type LonLat struct {
	Lon float64 `json:"lon" minimum:"5.7" maximum:"10.7"`
	Lat float64 `json:"lat" minimum:"45.65" maximum:"47.95"`
}

// Content is what a client submits for a route's geometry.
type Content struct {
	Profile string
	Anchors []Anchor
	Legs    []routing.Leg
}

// Totals are the route-wide numbers.
type Totals struct {
	DistanceM        float64 `json:"distance_m"`
	AscentM          float64 `json:"ascent_m"`
	DescentM         float64 `json:"descent_m"`
	DurationS        int     `json:"duration_s"`
	DurationReverseS int     `json:"duration_reverse_s"`
	EleMinM          float64 `json:"ele_min_m"`
	EleMaxM          float64 `json:"ele_max_m"`
	SACGrade         int     `json:"sac_grade"`
	SACMax           int     `json:"sac_max"`
}

// Meta is the descriptive part of a route.
type Meta struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Visibility  string `json:"visibility" enum:"private,unlisted,public"`
	// Tags of a stage route are its journey's.
	Tags []string `json:"tags"`
}

// Hike is when a route recorded with the app was hiked.
type Hike struct {
	At             time.Time `json:"at"`
	DurationS      int       `json:"duration_s" doc:"From the first to the last position, breaks included"`
	PlannedRouteID string    `json:"planned_route_id,omitempty" format:"uuid" doc:"The planned route that was followed"`
}

// Summary is a route in lists.
type Summary struct {
	ID            string `json:"id" format:"uuid"`
	OwnerUsername string `json:"owner_username"`
	Meta
	Profile   string    `json:"profile"`
	Totals    Totals    `json:"totals"`
	Version   int       `json:"version"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	// Hike is set for routes recorded with the app.
	Hike *Hike `json:"hike,omitempty"`
	// DoneOn is when the viewer hiked it: marked, recorded with the app,
	// or (journeys, for their owner and editors) all stages ticked off.
	// Set in lists of one's own and shared items and on GET.
	DoneOn *string `json:"done_on,omitempty" format:"date"`
}

// Route is a full route including its planner state.
type Route struct {
	Summary
	OwnerID    string `json:"-"`
	ShareToken string `json:"-"` // grants read access when visibility is unlisted
	// JourneyID is set for stage routes; the journey's visibility and share
	// token apply to them.
	JourneyID string        `json:"journey_id,omitempty"`
	Anchors   []Anchor      `json:"anchors"`
	Legs      []routing.Leg `json:"legs"`
	// Hidden are the start and end of a recorded hike as others see it
	// (ForOthers): nothing within PrivacyM of them is shown.
	Hidden []geo.Point `json:"-"`
}

// assembled is validated content ready to store.
type assembled struct {
	legs   []routing.Leg
	wkt    string // merged LINESTRING Z
	totals Totals
}

// Check validates content as saving it would and returns its legs with
// every number recomputed, and the route's totals.
func Check(c Content) ([]routing.Leg, Totals, error) {
	a, err := assemble(c)
	return a.legs, a.totals, err
}

func assemble(c Content) (assembled, error) {
	if c.Profile != "hike" && c.Profile != "alpine" {
		return assembled{}, invalid("unknown profile %q", c.Profile)
	}
	if len(c.Anchors) < 2 || len(c.Anchors) > MaxAnchors {
		return assembled{}, invalid("a route needs 2 to %d anchors", MaxAnchors)
	}
	if len(c.Legs) != len(c.Anchors)-1 {
		return assembled{}, invalid("%d anchors need %d legs, got %d", len(c.Anchors), len(c.Anchors)-1, len(c.Legs))
	}

	a := assembled{totals: Totals{EleMinM: math.Inf(1), EleMaxM: math.Inf(-1)}}
	var merged [][3]float64
	vertices := 0
	for i, raw := range c.Legs {
		vertices += len(raw.Coordinates)
		if vertices > MaxVertices {
			return assembled{}, invalid("route has more than %d points", MaxVertices)
		}
		l, err := normalizeLeg(raw)
		if err != nil {
			return assembled{}, fmt.Errorf("leg %d: %w", i+1, err)
		}
		coords := l.Coordinates
		if n := len(merged); n > 0 {
			last, first := merged[n-1], coords[0]
			gap := geo.Distance(geo.Point{Lon: last[0], Lat: last[1]}, geo.Point{Lon: first[0], Lat: first[1]})
			if gap > maxGap {
				return assembled{}, invalid("leg %d starts %.0f m from the end of leg %d", i+1, gap, i)
			}
			if gap < jointTolerance {
				coords = coords[1:] // shared joint
			}
		}
		merged = append(merged, coords...)
		a.legs = append(a.legs, l)
		addTotals(&a.totals, l)
	}

	var b strings.Builder
	b.WriteString("LINESTRING Z (")
	for i, c := range merged {
		if i > 0 {
			b.WriteByte(',')
		}
		fmt.Fprintf(&b, "%.6f %.6f %.1f", c[0], c[1], c[2])
	}
	b.WriteByte(')')
	a.wkt = b.String()
	return a, nil
}

func addTotals(t *Totals, l routing.Leg) {
	t.DistanceM += l.DistanceM
	t.AscentM += l.AscentM
	t.DescentM += l.DescentM
	t.DurationS += l.DurationS
	t.DurationReverseS += l.DurationReverseS
	t.EleMinM = min(t.EleMinM, l.EleMinM)
	t.EleMaxM = max(t.EleMaxM, l.EleMaxM)
	t.SACGrade = max(t.SACGrade, l.SAC.Grade)
	t.SACMax = max(t.SACMax, l.SAC.Max, l.SAC.Grade)
}

// jointTolerance (metres): consecutive legs closer than this share a vertex.
const jointTolerance = 0.5

// Line returns the whole route as one line, joints between legs not repeated.
func (r Route) Line() [][3]float64 {
	var out [][3]float64
	for _, l := range r.Legs {
		c := l.Coordinates
		if len(out) > 0 && len(c) > 0 {
			last := out[len(out)-1]
			if geo.Distance(geo.Point{Lon: last[0], Lat: last[1]}, geo.Point{Lon: c[0][0], Lat: c[0][1]}) < jointTolerance {
				c = c[1:]
			}
		}
		out = append(out, c...)
	}
	return out
}
