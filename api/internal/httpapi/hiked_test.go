package httpapi

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"testing"

	"github.com/tellbow/alvyo/api/internal/discover"
)

func TestHiked(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name string) *client {
		c := s.client(t)
		s.signup(c, name+"@example.ch", name)
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := s.db.Exec(ctx, q, args...); err != nil {
			t.Fatal(err)
		}
	}
	me, other := signup("hiker"), signup("other")
	create := func(c *client, title string, lon float64) (string, float64, float64, int) {
		t.Helper()
		code, b := c.do("POST", "/api/v1/routes", legsRoute(title, lon, 2, "T2"))
		if code != http.StatusCreated {
			t.Fatalf("create: %d %s", code, b)
		}
		var r struct {
			ID     string
			Totals struct {
				DistanceM float64 `json:"distance_m"`
				AscentM   float64 `json:"ascent_m"`
				DurationS int     `json:"duration_s"`
			}
		}
		_ = json.Unmarshal(b, &r)
		return r.ID, r.Totals.DistanceM, r.Totals.AscentM, r.Totals.DurationS
	}
	mark := func(c *client, path, day string) {
		t.Helper()
		if code, b := c.do("PUT", "/api/v1/"+path+"/done", map[string]any{"done_on": day}); code != http.StatusOK {
			t.Fatalf("mark %s: %d %s", path, code, b)
		}
	}
	hiked := func(c *client, query string) discover.Hiked {
		t.Helper()
		code, b := c.do("GET", "/api/v1/me/hiked"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("hiked: %d %s", code, b)
		}
		var h discover.Hiked
		if err := json.Unmarshal(b, &h); err != nil {
			t.Fatal(err)
		}
		return h
	}

	if h := hiked(me, ""); h.Total.Hikes != 0 || len(h.Years) != 0 || len(h.Items) != 0 {
		t.Errorf("nothing hiked yet: %+v", h)
	}

	// A route hiked twice counts twice; planned and untouched routes not at all.
	twice, dist, ascent, dur := create(me, "Zweimal", 8.00)
	create(me, "Nur geplant", 8.01)
	mark(me, "routes/"+twice, "2025-06-01")
	mark(me, "routes/"+twice, "2026-06-01")
	// A recording counts with its own time; the mark of its plan on the same
	// day does not count on top, a mark on another day does.
	plan, _, _, _ := create(me, "Plan", 8.02)
	rec, recDist, _, _ := create(me, "Aufgezeichnet", 8.03)
	exec(`UPDATE routes SET hiked_at = '2026-07-01 12:00+02', hiked_s = 3600, planned_route_id = $2 WHERE id = $1`, rec, plan)
	mark(me, "routes/"+plan, "2026-07-01")

	h := hiked(me, "")
	if h.Total.Hikes != 3 || len(h.Items) != 3 {
		t.Fatalf("hikes: %+v", h.Total)
	}
	if len(h.Years) != 2 || h.Years[0].Year != 2026 || h.Years[0].Hikes != 2 || h.Years[1].Year != 2025 || h.Years[1].Hikes != 1 {
		t.Errorf("years: %+v", h.Years)
	}
	if want := dist*2 + recDist; h.Total.DistanceM != want {
		t.Errorf("distance: %v, want %v", h.Total.DistanceM, want)
	}
	if h.Total.AscentM < ascent*2 || h.Total.TimeS != dur*2+3600 || h.Total.LongestM != dist || h.Total.HighestM <= 0 {
		t.Errorf("totals: %+v (ascent %v, time %v)", h.Total, ascent, dur)
	}
	if len(h.Items[0].Lines) != 1 || len(h.Items[0].Lines[0]) < 2 || h.Items[0].On != "2026-07-01" {
		t.Errorf("newest item: %+v", h.Items[0])
	}

	// A year: its hikes only, the totals of all years stay.
	h = hiked(me, "?year=2025")
	if len(h.Items) != 1 || h.Items[0].Title != "Zweimal" || h.Total.Hikes != 3 {
		t.Errorf("2025: %+v", h)
	}

	// At one's pace, unless recorded.
	exec(`UPDATE users SET speed_factor = 2 WHERE username = 'hiker'`)
	if got := hiked(me, "").Total.TimeS; got != dur*4+3600 {
		t.Errorf("at pace 2: %d, want %d", got, dur*4+3600)
	}
	exec(`UPDATE users SET speed_factor = 1 WHERE username = 'hiker'`)

	// Someone else's: without the ends of a recording; gone once it is private.
	code, b := other.do("POST", "/api/v1/routes", legsRoute("Fremd", 8.10, 40, "T2"))
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, b)
	}
	var created struct{ ID string }
	_ = json.Unmarshal(b, &created)
	theirs := created.ID
	exec(`UPDATE routes SET visibility = 'public', hiked_at = now() - interval '1 year', hiked_s = 60 WHERE id = $1`, theirs)
	mark(me, "routes/"+theirs, "2024-05-01")
	h = hiked(me, "?year=2024")
	if len(h.Items) != 1 || len(h.Items[0].Lines) == 0 {
		t.Fatalf("someone else's: %+v", h.Items)
	}
	var startLon, startLat float64
	if err := s.db.QueryRow(ctx, `SELECT ST_X(ST_StartPoint(geom)), ST_Y(ST_StartPoint(geom)) FROM routes WHERE id = $1`, theirs).Scan(&startLon, &startLat); err != nil {
		t.Fatal(err)
	}
	for _, l := range h.Items[0].Lines {
		for _, p := range l {
			if math.Abs(p[0]-startLon)+math.Abs(p[1]-startLat) < 0.001 {
				t.Errorf("the recording's start shows: %v", p)
			}
		}
	}
	// A recording too short to show anything still counts.
	var shortRoute struct{ ID string }
	_, b = other.do("POST", "/api/v1/routes", legsRoute("Kurz", 8.11, 1, "T2"))
	_ = json.Unmarshal(b, &shortRoute)
	exec(`UPDATE routes SET visibility = 'public', hiked_at = now() - interval '1 year', hiked_s = 60 WHERE id = $1`, shortRoute.ID)
	mark(me, "routes/"+shortRoute.ID, "2024-05-02")
	h = hiked(me, "?year=2024")
	if len(h.Items) != 2 || h.Items[0].Title != "Kurz" || len(h.Items[0].Lines) != 0 {
		t.Errorf("too short to show: %+v", h.Items)
	}
	exec(`DELETE FROM done_marks WHERE route_id = $1`, shortRoute.ID)
	exec(`UPDATE routes SET visibility = 'private' WHERE id = $1`, theirs)
	if got := hiked(me, "?year=2024"); len(got.Items) != 0 || len(got.Years) != 2 {
		t.Errorf("no longer visible: %+v", got)
	}

	// Journeys: ticked stages on their day, a first mark adds the rest, a later
	// one is the whole journey again; skipped stages do not count.
	_, b = me.do("POST", "/api/v1/journeys", map[string]any{"title": "Via", "visibility": "public"})
	j := decodeJourney(t, b)
	stage := func(title string, lon float64, position int, status, day any) {
		t.Helper()
		id, _, _, _ := create(me, title, lon)
		exec(`UPDATE routes SET journey_id = $1 WHERE id = $2`, j.ID, id)
		exec(`INSERT INTO stages (journey_id, position, status, done_on, route_id) VALUES ($1, $2, $3, $4, $5)`, j.ID, position, status, day, id)
	}
	stage("Eins", 8.20, 0, "done", "2023-07-01")
	stage("Zwei", 8.21, 1, "planned", nil)
	stage("Drei", 8.22, 2, "skipped", nil)
	count := func(year string) int {
		t.Helper()
		n := 0
		for _, it := range hiked(me, "?year="+year).Items {
			if it.Kind == "journey" {
				n++
			}
		}
		return n
	}
	if got := count("2023"); got != 1 {
		t.Errorf("ticked stage: %d", got)
	}
	mark(me, "journeys/"+j.ID, "2023-07-02") // finished by the mark: only «Zwei» is added
	if got := count("2023"); got != 2 {
		t.Errorf("after the first mark: %d, want 2", got)
	}
	mark(me, "journeys/"+j.ID, "2024-07-02") // again: both stages not skipped
	if got := count("2024"); got != 2 {
		t.Errorf("hiked again: %d, want 2", got)
	}

	// Only one's own.
	if h := hiked(other, ""); h.Total.Hikes != 2 || h.Items[1].Title != "Fremd" && h.Items[0].Title != "Fremd" {
		t.Errorf("other's: %+v", h)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/me/hiked", nil); code != http.StatusUnauthorized {
		t.Errorf("logged out: %d", code)
	}
}
