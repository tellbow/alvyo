package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"
	_ "time/tzdata" // Europe/Zurich, independent of the container image

	"github.com/danielgtaylor/huma/v2"

	"github.com/tellbow/odysgeh/swiss/ojp"
)

// Planner finds public transport connections (ojp.Client).
type Planner interface {
	Trips(ctx context.Context, q ojp.Query) ([]ojp.Trip, error)
}

// tripCacheTTL: timetables rarely change within minutes, and the OJP quota
// is small (50 requests per minute for the whole platform).
const tripCacheTTL = 10 * time.Minute

type connectionsInput struct {
	From   string `query:"from" required:"true" pattern:"^[0-9]{7}$" doc:"Didok number of the departure stop"`
	To     string `query:"to" required:"true" pattern:"^[0-9]{7}$" doc:"Didok number of the arrival stop"`
	Date   string `query:"date" required:"true" pattern:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" doc:"YYYY-MM-DD"`
	Time   string `query:"time" pattern:"^[0-9]{2}:[0-9]{2}$" default:"08:00" doc:"HH:MM, Swiss time"`
	Arrive bool   `query:"arrive" doc:"The time is the latest arrival instead of the earliest departure"`
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
		Summary:     "Public transport connections between two stops",
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
		key := strings.Join([]string{in.From, in.To, in.Date, in.Time, map[bool]string{true: "a", false: "d"}[in.Arrive]}, "|")
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
		trips, err := d.Planner.Trips(ctx, ojp.Query{From: in.From, To: in.To, At: at, Arrive: in.Arrive})
		if err != nil {
			slog.WarnContext(ctx, "connections", "err", err)
			return nil, huma.Error502BadGateway("the journey planner did not answer; use the SBB link")
		}
		cache.put(key, trips, now)
		out.Body.Trips = trips
		return out, nil
	})
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
