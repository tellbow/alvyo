package httpapi

import (
	"context"
	"log/slog"
	"math"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
	_ "time/tzdata" // Europe/Zurich, independent of the container image

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/alvyo/api/internal/places"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/ojp"
)

// Planner finds public transport connections (ojp.Client).
type Planner interface {
	Trips(ctx context.Context, q ojp.Query) ([]ojp.Trip, error)
}

// tripCacheTTL: timetables rarely change within minutes, and the OJP quota
// is small (50 requests per minute for the whole platform).
const tripCacheTTL = 10 * time.Minute

type connectionsInput struct {
	From     string `query:"from" required:"true" pattern:"^([0-9]{7}|-?[0-9]{1,3}(\\.[0-9]{1,7})?,-?[0-9]{1,2}(\\.[0-9]{1,7})?)$" doc:"Didok number of the departure stop, or a position as lon,lat"`
	To       string `query:"to" required:"true" pattern:"^([0-9]{7}|-?[0-9]{1,3}(\\.[0-9]{1,7})?,-?[0-9]{1,2}(\\.[0-9]{1,7})?)$" doc:"Didok number of the arrival stop, or a position as lon,lat"`
	FromName string `query:"from_name" maxLength:"60" doc:"Name of a departure position, for the walk from it"`
	ToName   string `query:"to_name" maxLength:"60" doc:"Name of an arrival position"`
	Date     string `query:"date" required:"true" pattern:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" doc:"YYYY-MM-DD"`
	Time     string `query:"time" pattern:"^[0-9]{2}:[0-9]{2}$" default:"08:00" doc:"HH:MM, Swiss time"`
	Arrive   bool   `query:"arrive" doc:"The time is the latest arrival instead of the earliest departure"`
	Lines    bool   `query:"lines" doc:"With the way of each leg (track), to draw them"`
	// Trailhead names the side that is a route's start or end (a position):
	// when the planner reaches it from no stop, the trips go to the stop
	// nearby with the shortest hike and add the hike (feedback issue 89).
	Trailhead string `query:"trailhead" enum:"from,to" doc:"The side that is a route's start (to) or end (from): without a connection there, one to the nearby stop with the shortest hike (up to 2 h) and the hike"`
}

// place reads a from or to parameter: a stop's Didok number, or a position
// as lon,lat (an address: the planner adds the walk to the stop).
func place(v, name string) ojp.Place {
	lon, lat, ok := strings.Cut(v, ",")
	if !ok {
		return ojp.Stop(v)
	}
	p := ojp.Place{Name: name}
	p.Lon, _ = strconv.ParseFloat(lon, 64)
	p.Lat, _ = strconv.ParseFloat(lat, 64)
	return p
}

type connectionsOutput struct {
	Body struct {
		Trips []ojp.Trip `json:"trips"`
	}
}

func registerConnections(api huma.API, d Deps) {
	cache := &tripCache{entries: map[string]tripEntry{}, max: 2000}
	zurich, err := time.LoadLocation("Europe/Zurich")
	if err != nil {
		panic(err) // cannot happen: time/tzdata is linked in
	}

	huma.Register(api, huma.Operation{
		OperationID: "find-connections", Method: http.MethodGet, Path: "/connections",
		Summary:     "Public transport connections between two stops or positions",
		Description: "From the Swiss Open Journey Planner; answers are cached for 10 minutes. 503 when not configured.",
		Tags:        []string{"places"},
	}, func(ctx context.Context, in *connectionsInput) (*connectionsOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if d.Planner == nil {
			return nil, huma.Error503ServiceUnavailable("public transport connections are not configured")
		}
		at, err := time.ParseInLocation("2006-01-02 15:04", in.Date+" "+in.Time, zurich)
		if err != nil {
			return nil, huma.Error422UnprocessableEntity("invalid date or time")
		}
		from, to := place(in.From, in.FromName), place(in.To, in.ToName)
		if !inRange(from) || !inRange(to) {
			return nil, huma.Error422UnprocessableEntity("a position is out of range")
		}
		key := strings.Join([]string{in.From, in.FromName, in.To, in.ToName, in.Date, in.Time,
			map[bool]string{true: "a", false: "d"}[in.Arrive], map[bool]string{true: "l", false: ""}[in.Lines], in.Trailhead}, "|")
		out := &connectionsOutput{}
		now := time.Now()
		if trips, ok := cache.get(key, now); ok {
			out.Body.Trips = trips
			return out, nil
		}
		if !d.Limits.ConnectionsUser.Allow(u.ID.String()) || !d.Limits.ConnectionsAll.Allow("all") {
			return nil, huma.Error429TooManyRequests("too many connection searches; try again in a minute")
		}
		ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
		defer cancel()
		q := ojp.Query{From: from, To: to, At: at, Arrive: in.Arrive, Lines: in.Lines}
		trips, err := d.Planner.Trips(ctx, q)
		if err != nil {
			slog.WarnContext(ctx, "connections", "err", err)
			return nil, huma.Error502BadGateway("the journey planner did not answer; use the SBB link")
		}
		if len(trips) == 0 && in.Trailhead != "" {
			if hiked := hikeTrips(ctx, d, q, in.Trailhead == "to", float64(u.SpeedFactor)); hiked != nil {
				trips = hiked
			}
		}
		cache.put(key, trips, now)
		out.Body.Trips = trips
		return out, nil
	})
}

// A hike from a stop to a route's start or back to one: at most 2 h of
// Swiss hiking time, so stops within 9 km (straight) are enough.
const (
	maxHikeS    = 2 * 3600
	hikeRadiusM = 9000
	hikeStops   = 3
)

// hikeTrips is for a route's start or end out of the planner's reach, high
// on a mountain: the trips to (toStart) or from the nearby stop with the
// shortest hike that has any, and the hike as their last or first leg. The
// times shift by the hike, at the user's pace. Nil when no stop fits.
func hikeTrips(ctx context.Context, d Deps, q ojp.Query, toStart bool, pace float64) []ojp.Trip {
	trail := q.From
	if toStart {
		trail = q.To
	}
	if d.Router == nil || d.Places == nil || trail.Ref != "" {
		return nil
	}
	if pace <= 0 {
		pace = 1
	}
	stops, err := d.Places.Nearby(ctx, places.Query{Lon: trail.Lon, Lat: trail.Lat,
		Kinds: []string{"pt_stop"}, Limit: hikeStops, RadiusM: hikeRadiusM})
	if err != nil {
		slog.WarnContext(ctx, "stops near a trailhead", "err", err)
		return nil
	}
	type hike struct {
		stop places.Place
		leg  routing.Leg
	}
	var hikes []hike
	here := geo.Point{Lon: trail.Lon, Lat: trail.Lat}
	for _, s := range stops {
		if s.Ref == "" {
			continue
		}
		from, to := geo.Point{Lon: s.At[0], Lat: s.At[1]}, here
		if !toStart {
			from, to = to, from
		}
		leg, err := d.Router.Leg(ctx, routing.LegRequest{From: from, To: to, Profile: "hike"})
		if err != nil || leg.DurationS > maxHikeS {
			continue
		}
		hikes = append(hikes, hike{s, leg})
	}
	slices.SortFunc(hikes, func(a, b hike) int { return a.leg.DurationS - b.leg.DurationS })
	// The nearest by hike may have no service that day (a lift closed for
	// the season): then the next.
	for _, h := range hikes {
		if !d.Limits.ConnectionsAll.Allow("all") {
			return nil
		}
		minutes := int(math.Round(float64(h.leg.DurationS) * pace / 60))
		walk := time.Duration(minutes) * time.Minute
		sq := q
		if toStart {
			sq.To = ojp.Stop(h.stop.Ref)
			if q.Arrive {
				sq.At = q.At.Add(-walk)
			}
		} else {
			sq.From = ojp.Stop(h.stop.Ref)
			if !q.Arrive {
				sq.At = q.At.Add(walk)
			}
		}
		trips, err := d.Planner.Trips(ctx, sq)
		if err != nil {
			slog.WarnContext(ctx, "connections to a stop near a trailhead", "err", err)
			continue
		}
		if len(trips) == 0 {
			continue
		}
		leg := ojp.Leg{Kind: "walk", Hike: true, From: h.stop.Name, To: trail.Name, DurationMin: minutes,
			AscentM: math.Round(h.leg.AscentM), DescentM: math.Round(h.leg.DescentM)}
		if !toStart {
			leg.From, leg.To = trail.Name, h.stop.Name
		}
		if q.Lines {
			for _, c := range h.leg.Coordinates {
				leg.Track = append(leg.Track, [2]float64{c[0], c[1]})
			}
		}
		for i := range trips {
			t := &trips[i]
			if toStart {
				t.Legs = append(t.Legs, leg)
				t.End = t.End.Add(walk)
			} else {
				t.Legs = append([]ojp.Leg{leg}, t.Legs...)
				t.Start = t.Start.Add(-walk)
			}
			t.Duration += walk
		}
		return trips
	}
	return nil
}

func inRange(p ojp.Place) bool {
	return p.Ref != "" || (p.Lon >= -180 && p.Lon <= 180 && p.Lat >= -90 && p.Lat <= 90)
}

// tripCache keeps planner answers for tripCacheTTL.
type tripCache struct {
	mu      sync.Mutex
	entries map[string]tripEntry
	max     int
}

type tripEntry struct {
	trips []ojp.Trip
	until time.Time
}

func (c *tripCache) get(key string, now time.Time) ([]ojp.Trip, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || now.After(e.until) {
		return nil, false
	}
	return e.trips, true
}

func (c *tripCache) put(key string, trips []ojp.Trip, now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.max {
		for k, e := range c.entries {
			if now.After(e.until) {
				delete(c.entries, k)
			}
		}
		for k := range c.entries { // still full: drop arbitrary entries
			if len(c.entries) < c.max {
				break
			}
			delete(c.entries, k)
		}
	}
	c.entries[key] = tripEntry{trips: trips, until: now.Add(tripCacheTTL)}
}
