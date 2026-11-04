package httpapi

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"strings"
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
		code, b := c.do("POST", "/api/v1/routes", legsRoute(title, lon, 40, "T2"))
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

	testSharedHiked(t, s, me, other, theirs)

	// Only one's own.
	if h := hiked(other, ""); h.Total.Hikes != 2 || h.Items[1].Title != "Fremd" && h.Items[0].Title != "Fremd" {
		t.Errorf("other's: %+v", h)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/me/hiked", nil); code != http.StatusUnauthorized {
		t.Errorf("logged out: %d", code)
	}
}

// testSharedHiked: me has hiked the routes above, and other's public route theirs.
func testSharedHiked(t *testing.T, s *testServer, me, other *client, theirs string) {
	t.Helper()
	ctx := context.Background()
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := s.db.Exec(ctx, q, args...); err != nil {
			t.Fatal(err)
		}
	}
	type shared struct {
		Total        *discover.HikedTotals
		Years        []discover.HikedTotals
		Lines        [][][2]float64
		Achievements *discover.Achievements
	}
	anon := s.client(t)
	get := func(c *client) (int, shared, string) {
		t.Helper()
		code, b := c.do("GET", "/api/v1/users/hiker/hiked", nil)
		var out shared
		if code == http.StatusOK {
			if err := json.Unmarshal(b, &out); err != nil {
				t.Fatal(err)
			}
		}
		return code, out, string(b)
	}
	set := func(body map[string]any) {
		t.Helper()
		if code, b := me.do("PATCH", "/api/v1/me", body); code != http.StatusOK {
			t.Fatalf("settings: %d %s", code, b)
		}
	}
	profileShared := func(c *client) bool {
		t.Helper()
		_, b := c.do("GET", "/api/v1/users/hiker", nil)
		var p struct {
			HikedShared bool `json:"hiked_shared"`
		}
		_ = json.Unmarshal(b, &p)
		return p.HikedShared
	}

	// Nothing by default, for anyone, oneself included.
	for name, c := range map[string]*client{"self": me, "other": other, "anonymous": anon} {
		if code, _, _ := get(c); code != http.StatusNotFound {
			t.Errorf("by default, %s: %d", name, code)
		}
	}
	if code, b := me.do("PATCH", "/api/v1/me", map[string]any{"share_map": "everybody"}); code != http.StatusUnprocessableEntity {
		t.Errorf("an unknown level: %d %s", code, b)
	}

	// For friends: not for others. Each choice on its own.
	set(map[string]any{"share_stats": "friends"})
	if code, _, _ := get(other); code != http.StatusNotFound || profileShared(other) {
		t.Errorf("not friends yet: %d", code)
	}
	if code, b := me.do("PUT", "/api/v1/users/other/friend", nil); code != http.StatusOK && code != http.StatusNoContent {
		t.Fatalf("friend request: %d %s", code, b)
	}
	if code, b := other.do("PUT", "/api/v1/users/hiker/friend", nil); code != http.StatusOK && code != http.StatusNoContent {
		t.Fatalf("friend accept: %d %s", code, b)
	}
	code, got, body := get(other)
	if code != http.StatusOK || got.Total == nil || got.Total.Hikes == 0 || len(got.Years) == 0 || got.Lines != nil || got.Achievements != nil {
		t.Errorf("numbers for a friend: %d %s", code, body)
	}
	if !profileShared(other) {
		t.Error("the profile should say so")
	}
	if code, _, _ := get(anon); code != http.StatusNotFound {
		t.Errorf("numbers for friends, anonymous: %d", code)
	}

	// The map, for all: plain lines, 500 m cut, without someone else's private
	// route (made so here), without a title or a date anywhere.
	set(map[string]any{"share_stats": "nobody", "share_map": "public"})
	code, got, body = get(anon)
	if code != http.StatusOK || got.Total != nil || got.Achievements != nil || len(got.Lines) == 0 {
		t.Fatalf("the map for all: %d %s", code, body)
	}
	for _, leak := range []string{"Zweimal", "Aufgezeichnet", "Plan", "Via", "2025-", "2026-", "on\":"} {
		if strings.Contains(body, leak) {
			t.Errorf("%q in what is shared: %s", leak, body[:200])
		}
	}
	// The test's routes run due east, so a line covers a range of longitudes.
	covers := func(lines [][][2]float64, lon float64) bool {
		for _, l := range lines {
			if min(l[0][0], l[len(l)-1][0]) <= lon && lon <= max(l[0][0], l[len(l)-1][0]) {
				return true
			}
		}
		return false
	}
	// Zweimal starts at 8.00 and no other route comes near; 500 m are 0.0065°.
	if covers(got.Lines, 8.003) || !covers(got.Lines, 8.01) {
		t.Errorf("a planned route without the first 500 m: %v", got.Lines)
	}
	// theirs is marked and public: shown. Otherwise not, though still hiked.
	exec(`UPDATE routes SET visibility = 'public' WHERE id = $1`, theirs)
	if _, got, _ = get(anon); !covers(got.Lines, 8.15) {
		t.Errorf("someone else's public route should show")
	}
	exec(`UPDATE routes SET visibility = 'unlisted' WHERE id = $1`, theirs)
	if _, got, _ = get(anon); covers(got.Lines, 8.15) {
		t.Errorf("someone else's route that is not public shows on the shared map")
	}

	// A private profile: public means friends.
	exec(`UPDATE users SET profile_public = false WHERE username = 'hiker'`)
	if code, _, _ := get(anon); code != http.StatusNotFound {
		t.Errorf("private profile, anonymous: %d", code)
	}
	if code, _, _ := get(other); code != http.StatusOK {
		t.Errorf("private profile, friend: %d", code)
	}
	exec(`UPDATE users SET profile_public = true WHERE username = 'hiker'`)

	// Achievements: what the hikes passed, and nothing else. Zweimal is at 8.00.
	var lon, lat float64
	if err := s.db.QueryRow(ctx, `SELECT ST_X(ST_LineInterpolatePoint(ST_Force2D(geom), 0.5)), ST_Y(ST_LineInterpolatePoint(ST_Force2D(geom), 0.5)) FROM routes WHERE title = 'Zweimal'`).Scan(&lon, &lat); err != nil {
		t.Fatal(err)
	}
	exec(`INSERT INTO pois (kind, name, ele, source_id, geom) VALUES
		('peak', 'Nahgipfel', 2500, 't1', ST_SetSRID(ST_MakePoint($1, $2), 4326)),
		('peak', 'Hochgipfel', 3000, 't2', ST_SetSRID(ST_MakePoint($1, $2), 4326)),
		('peak', '', 2000, 't3', ST_SetSRID(ST_MakePoint($1, $2), 4326)),
		('peak', 'Ferngipfel', 4000, 't4', ST_SetSRID(ST_MakePoint($1, $2 + 0.05), 4326)),
		('viewpoint', 'Aussicht', 1000, 't5', ST_SetSRID(ST_MakePoint($1, $2), 4326))`, lon, lat)
	exec(`INSERT INTO places (kind, name, source, source_id, geom) VALUES
		('hut', 'Nahhütte', 'osm', 't1', ST_SetSRID(ST_MakePoint($1, $2), 4326)),
		('hut', 'Fernhütte', 'osm', 't2', ST_SetSRID(ST_MakePoint($1, $2 + 0.05), 4326)),
		('hotel', 'Hotel', 'osm', 't3', ST_SetSRID(ST_MakePoint($1, $2), 4326))`, lon, lat)
	var twice string
	if err := s.db.QueryRow(ctx, `SELECT id FROM routes WHERE title = 'Zweimal'`).Scan(&twice); err != nil {
		t.Fatal(err)
	}
	var unhiked string
	if err := s.db.QueryRow(ctx, `SELECT id FROM routes WHERE title = 'Nur geplant'`).Scan(&unhiked); err != nil {
		t.Fatal(err)
	}
	exec(`INSERT INTO official (nr, kind, route_id, hash) VALUES ('1', 'national', $1, ''), ('2', 'national', $2, '')`, twice, unhiked)

	code, b := me.do("GET", "/api/v1/me/achievements", nil)
	var a discover.Achievements
	if code != http.StatusOK || json.Unmarshal(b, &a) != nil {
		t.Fatalf("achievements: %d %s", code, b)
	}
	if len(a.Summits) != 2 || a.Summits[0].Name != "Hochgipfel" || a.Summits[1].Name != "Nahgipfel" {
		t.Errorf("summits: %+v", a.Summits)
	}
	if len(a.Huts) != 1 || a.Huts[0] != "Nahhütte" {
		t.Errorf("huts: %+v", a.Huts)
	}
	// 8.0, 46.5 and thereabouts: the lines of this test lie in Bern or Valais.
	if a.CantonsTotal != 26 || len(a.Cantons) == 0 {
		t.Errorf("cantons: %+v", a.Cantons)
	}
	if len(a.Official) != 1 || a.Official[0] != (discover.OfficialDone{Kind: "national", Done: 1, Total: 2}) {
		t.Errorf("official: %+v", a.Official)
	}
	var n int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM cantons WHERE ST_IsValid(geom)`).Scan(&n); err != nil || n != 26 {
		t.Errorf("valid cantons: %d %v", n, err)
	}

	// Shared on its own.
	set(map[string]any{"share_map": "nobody", "share_achievements": "friends"})
	code, got, body = get(other)
	if code != http.StatusOK || got.Lines != nil || got.Total != nil || got.Achievements == nil || len(got.Achievements.Summits) != 2 {
		t.Errorf("achievements for a friend: %d %s", code, body)
	}

	// Blocking ends a friendship, and with it what was shared with friends.
	if code, b := me.do("PUT", "/api/v1/users/other/block", nil); code != http.StatusOK && code != http.StatusNoContent {
		t.Fatalf("block: %d %s", code, b)
	}
	if code, _, _ := get(other); code != http.StatusNotFound {
		t.Errorf("blocked: %d", code)
	}
}
