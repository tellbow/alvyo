package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"testing"
)

// lineRoute is a route of about 150 m heading east from lon0 at lat, with
// the given SAC grade on all of it.
func lineRoute(title, visibility string, lon0, lat float64, sac string) map[string]any {
	leg := routeLeg(lon0)
	coords := [][3]float64{}
	for i := 0; i <= 4; i++ {
		coords = append(coords, [3]float64{lon0 + float64(i)*0.0005, lat, 1000 + float64(i)*5})
	}
	leg["coordinates"] = coords
	details := leg["details"].(map[string]any)
	details["sac"] = []map[string]any{{"from": 0, "to": 4, "value": sac}}
	return map[string]any{
		"title": title, "visibility": visibility, "profile": "hike",
		"anchors": []map[string]any{{"lon": lon0, "lat": lat}, {"lon": lon0 + 0.002, "lat": lat}},
		"legs":    []map[string]any{leg},
	}
}

type discoverResp struct {
	Items []struct {
		Kind          string         `json:"kind"`
		ID            string         `json:"id"`
		Title         string         `json:"title"`
		OwnerUsername string         `json:"owner_username"`
		SACGrade      int            `json:"sac_grade"`
		Stages        int            `json:"stages"`
		Lines         [][][2]float64 `json:"lines"`
	} `json:"items"`
	More bool `json:"more"`
}

func (r discoverResp) titles() string {
	var t []string
	for _, it := range r.Items {
		t = append(t, it.Title)
	}
	return strings.Join(t, ",")
}

func TestDiscover(t *testing.T) {
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
	create := func(c *client, body map[string]any) string {
		t.Helper()
		code, resp := c.do("POST", "/api/v1/routes", body)
		if code != http.StatusCreated {
			t.Fatalf("create %v: %d %s", body["title"], code, resp)
		}
		var r savedRoute
		_ = json.Unmarshal(resp, &r)
		return r.ID
	}

	hiker, quiet, spammer := signup("wanderer"), signup("quiet"), signup("spammer")
	create(hiker, lineRoute("Nahe", "public", 8.000, 46.6, "T2"))
	create(hiker, lineRoute("Schwer", "public", 8.010, 46.6, "T4"))
	create(hiker, lineRoute("Geheim", "private", 8.001, 46.6, "T2"))
	create(hiker, lineRoute("Link", "unlisted", 8.002, 46.6, "T2"))
	create(hiker, lineRoute("Fern", "public", 9.000, 46.6, "T2"))
	create(quiet, lineRoute("Still", "private", 8.004, 46.6, "T2"))
	create(spammer, lineRoute("Werbung", "public", 8.005, 46.6, "T2"))
	if _, err := s.db.Exec(ctx, `UPDATE users SET banned_at = now() WHERE username = 'spammer'`); err != nil {
		t.Fatal(err)
	}

	// A public journey with one stage; the stage route is found as the journey.
	_, body := hiker.do("POST", "/api/v1/journeys", map[string]any{"title": "Reise", "visibility": "public"})
	var j journeyResp
	_ = json.Unmarshal(body, &j)
	_, body = hiker.do("POST", "/api/v1/journeys/"+j.ID+"/stages", map[string]any{})
	j = decodeJourney(t, body)
	stage := lineRoute("", "", 8.020, 46.6, "T2")
	delete(stage, "title")
	delete(stage, "visibility")
	if code, body := hiker.do("POST", "/api/v1/journeys/"+j.ID+"/stages/"+j.StageList[0].ID+"/route", stage); code != http.StatusOK {
		t.Fatalf("stage route: %d %s", code, body)
	}

	anon := s.client(t)
	search := func(query string) discoverResp {
		t.Helper()
		code, body := anon.do("GET", "/api/v1/discover?bbox=7.99,46.59,8.03,46.61"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("discover %s: %d %s", query, code, body)
		}
		var r discoverResp
		_ = json.Unmarshal(body, &r)
		return r
	}

	// Nearest to the centre (8.01, 46.6) first.
	r := search("")
	if got := r.titles(); got != "Schwer,Nahe,Reise" || r.More {
		t.Fatalf("all: %s (more %v)", got, r.More)
	}
	if it := r.Items[2]; it.Kind != "journey" || it.Stages != 1 || it.OwnerUsername != "wanderer" || len(it.Lines) != 1 || len(it.Lines[0]) < 2 {
		t.Errorf("journey item: %+v", it)
	}
	if got := search("&sac_max=3").titles(); got != "Nahe,Reise" {
		t.Errorf("up to T3: %s", got)
	}
	if got := search("&kind=route").titles(); got != "Schwer,Nahe" {
		t.Errorf("routes only: %s", got)
	}
	if got := search("&kind=journey").titles(); got != "Reise" {
		t.Errorf("journeys only: %s", got)
	}
	if got := search("&duration_max=60").titles(); got != "" {
		t.Errorf("under a minute: %s", got)
	}
	if got := search("&duration_min=60&duration_max=3600").titles(); got != "Schwer,Nahe,Reise" {
		t.Errorf("one minute to an hour: %s", got)
	}
	for _, bad := range []string{"8,46,7,47", "8,46,9", "a,b,c,d"} {
		if code, _ := anon.do("GET", "/api/v1/discover?bbox="+bad, nil); code != http.StatusUnprocessableEntity {
			t.Errorf("bbox %s: %d, want 422", bad, code)
		}
	}

	// Profiles list public routes and journeys only.
	code, body := anon.do("GET", "/api/v1/users/wanderer", nil)
	var p struct {
		Username    string `json:"username"`
		DisplayName string `json:"display_name"`
		Routes      []struct {
			Title string `json:"title"`
		} `json:"routes"`
		Journeys []struct {
			ID    string `json:"id"`
			Title string `json:"title"`
		} `json:"journeys"`
		Outlines map[string][][][2]float64 `json:"outlines"`
	}
	_ = json.Unmarshal(body, &p)
	if code != http.StatusOK || p.Username != "wanderer" || len(p.Routes) != 3 || len(p.Journeys) != 1 || p.Journeys[0].Title != "Reise" {
		t.Fatalf("profile: %d %s", code, body)
	}
	// A thumbnail for each item listed, none for the private or unlisted ones.
	if len(p.Outlines) != 4 || len(p.Outlines[p.Journeys[0].ID]) != 1 || len(p.Outlines[p.Journeys[0].ID][0]) < 2 {
		t.Errorf("outlines: %v", p.Outlines)
	}
	if strings.Contains(string(body), "@example.ch") {
		t.Error("the profile shows the e-mail address")
	}
	for _, name := range []string{"quiet", "spammer", "nobody"} {
		if code, _ := anon.do("GET", "/api/v1/users/"+name, nil); code != http.StatusNotFound {
			t.Errorf("profile %s: %d, want 404", name, code)
		}
	}
	// Signed in, a public profile shows without anything published: the
	// search finds it.
	if code, body := hiker.do("GET", "/api/v1/users/quiet", nil); code != http.StatusOK {
		t.Errorf("quiet signed in: %d %s", code, body)
	}
	// A private one only to whom it asked to be friends.
	if _, err := s.db.Exec(ctx, `UPDATE users SET profile_public = false WHERE username = 'quiet'`); err != nil {
		t.Fatal(err)
	}
	if code, _ := hiker.do("GET", "/api/v1/users/quiet", nil); code != http.StatusNotFound {
		t.Errorf("quiet private: %d, want 404", code)
	}
	if code, body := quiet.do("PUT", "/api/v1/users/wanderer/friend", nil); code != http.StatusOK {
		t.Fatalf("quiet asks: %d %s", code, body)
	}
	if code, body := hiker.do("GET", "/api/v1/users/quiet", nil); code != http.StatusOK {
		t.Errorf("quiet private, asking: %d %s", code, body)
	}

	// The sitemap: public items of users not banned, and their profiles;
	// no stage routes, nothing private or unlisted.
	for _, c := range []struct{ title, visibility string }{{"Gipfel", "public"}, {"Entwurf", "private"}} {
		if code, body := hiker.do("POST", "/api/v1/collections", map[string]any{"title": c.title, "visibility": c.visibility}); code != http.StatusCreated {
			t.Fatalf("collection %s: %d %s", c.title, code, body)
		}
	}
	code, body = anon.do("GET", "/api/v1/sitemap", nil)
	var sm struct {
		Entries []struct{ Kind, ID string } `json:"entries"`
	}
	_ = json.Unmarshal(body, &sm)
	kinds := map[string]int{}
	for _, e := range sm.Entries {
		kinds[e.Kind]++
		if e.Kind == "profile" && e.ID != "wanderer" {
			t.Errorf("sitemap profile %s", e.ID)
		}
	}
	if code != http.StatusOK || kinds["route"] != 3 || kinds["journey"] != 1 || kinds["collection"] != 1 || kinds["profile"] != 1 {
		t.Errorf("sitemap: %d %v %s", code, kinds, body)
	}
}

// The profile lists what the viewer may open, and for friends what the user
// hiked, also of others (feedback issues 58 and 68).
func TestProfileShows(t *testing.T) {
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
	post := func(c *client, path string, body map[string]any) string {
		t.Helper()
		code, resp := c.do("POST", path, body)
		if code >= 300 {
			t.Fatalf("%s: %d %s", path, code, resp)
		}
		var r struct{ ID string }
		_ = json.Unmarshal(resp, &r)
		return r.ID
	}
	anna, bea, carl := signup("anna"), signup("bea"), signup("carl")
	post(anna, "/api/v1/routes", lineRoute("Offen", "public", 8.000, 46.6, "T2"))
	post(anna, "/api/v1/routes", lineRoute("Geheim", "private", 8.001, 46.6, "T2"))
	post(anna, "/api/v1/routes", lineRoute("Link", "unlisted", 8.002, 46.6, "T2"))
	forBea := post(anna, "/api/v1/routes", lineRoute("Für Bea", "private", 8.003, 46.6, "T2"))
	post(anna, "/api/v1/routes/"+forBea+"/grants", map[string]any{"username": "bea", "role": "viewer"})
	carlsPublic := post(carl, "/api/v1/routes", lineRoute("Carls Gipfel", "public", 8.004, 46.6, "T2"))
	carlsPrivate := post(carl, "/api/v1/routes", lineRoute("Carls Geheimnis", "private", 8.005, 46.6, "T2"))
	for _, id := range []string{carlsPublic, carlsPrivate} {
		post(carl, "/api/v1/routes/"+id+"/grants", map[string]any{"username": "anna", "role": "viewer"})
		if code, body := anna.do("PUT", "/api/v1/routes/"+id+"/done", map[string]any{"done_on": "2026-08-01"}); code != http.StatusOK {
			t.Fatalf("done: %d %s", code, body)
		}
	}
	post(anna, "/api/v1/collections", map[string]any{"title": "Sammlung", "visibility": "public"})
	post(anna, "/api/v1/collections", map[string]any{"title": "Entwurf", "visibility": "private"})

	type item struct {
		Title  string  `json:"title"`
		DoneOn *string `json:"done_on"`
	}
	profile := func(c *client) (routes, collections string, done int) {
		t.Helper()
		code, body := c.do("GET", "/api/v1/users/anna", nil)
		var p struct {
			Routes      []item                    `json:"routes"`
			Collections []item                    `json:"collections"`
			Outlines    map[string][][][2]float64 `json:"outlines"`
		}
		_ = json.Unmarshal(body, &p)
		if code != http.StatusOK || len(p.Outlines) != len(p.Routes) {
			t.Fatalf("profile: %d %s", code, body)
		}
		var r, cs []string
		for _, it := range p.Routes {
			r = append(r, it.Title)
			if it.DoneOn != nil {
				done++
			}
		}
		for _, it := range p.Collections {
			cs = append(cs, it.Title)
		}
		sort.Strings(r)
		return strings.Join(r, ","), strings.Join(cs, ","), done
	}

	// A stranger: the public ones, no hikes.
	if r, c, n := profile(s.client(t)); r != "Offen" || c != "Sammlung" || n != 0 {
		t.Errorf("stranger: %s / %s / %d", r, c, n)
	}
	// Bea also what anna shared with her; as a friend, the hike on carl's
	// public route, not on his private one.
	if r, _, n := profile(bea); r != "Für Bea,Offen" || n != 0 {
		t.Errorf("bea: %s / %d", r, n)
	}
	befriend := func(a, b *client, aName, bName string) {
		t.Helper()
		if code, body := a.do("PUT", "/api/v1/users/"+bName+"/friend", nil); code != http.StatusOK {
			t.Fatalf("friend: %d %s", code, body)
		}
		if code, body := b.do("PUT", "/api/v1/users/"+aName+"/friend", nil); code != http.StatusOK {
			t.Fatalf("friend: %d %s", code, body)
		}
	}
	befriend(anna, bea, "anna", "bea")
	if r, _, n := profile(bea); r != "Carls Gipfel,Für Bea,Offen" || n != 1 {
		t.Errorf("bea, friend: %s / %d", r, n)
	}
	// Carl may open his private route: as a friend he sees it among the hikes.
	befriend(anna, carl, "anna", "carl")
	if r, _, n := profile(carl); r != "Carls Geheimnis,Carls Gipfel,Offen" || n != 2 {
		t.Errorf("carl, friend: %s / %d", r, n)
	}
	// Hikes switched off: no hikes for friends.
	if _, err := s.db.Exec(ctx, `UPDATE users SET share_hikes = false WHERE username = 'anna'`); err != nil {
		t.Fatal(err)
	}
	if r, _, n := profile(bea); r != "Für Bea,Offen" || n != 0 {
		t.Errorf("bea, hikes off: %s / %d", r, n)
	}
}
