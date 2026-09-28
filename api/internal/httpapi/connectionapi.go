package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
	_ "time/tzdata" // Europe/Zurich, independent of the container image

	"github.com/danielgtaylor/huma/v2"

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
			map[bool]string{true: "a", false: "d"}[in.Arrive], map[bool]string{true: "l", false: ""}[in.Lines]}, "|")
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
		trips, err := d.Planner.Trips(ctx, ojp.Query{From: from, To: to, At: at, Arrive: in.Arrive, Lines: in.Lines})
		if err != nil {
			slog.WarnContext(ctx, "connections", "err", err)
			return nil, huma.Error502BadGateway("the journey planner did not answer; use the SBB link")
		}
		cache.put(key, trips, now)
		out.Body.Trips = trips
		return out, nil
	})
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
