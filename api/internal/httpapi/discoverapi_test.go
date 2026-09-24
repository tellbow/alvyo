package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
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
		if code, body := c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name)); code != http.StatusCreated {
			t.Fatalf("signup %s: %d %s", name, code, body)
		}
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
			Title string `json:"title"`
		} `json:"journeys"`
	}
	_ = json.Unmarshal(body, &p)
	if code != http.StatusOK || p.Username != "wanderer" || len(p.Routes) != 3 || len(p.Journeys) != 1 || p.Journeys[0].Title != "Reise" {
		t.Fatalf("profile: %d %s", code, body)
	}
	if strings.Contains(string(body), "@example.ch") {
		t.Error("the profile shows the e-mail address")
	}
	for _, name := range []string{"quiet", "spammer", "nobody"} {
		if code, _ := anon.do("GET", "/api/v1/users/"+name, nil); code != http.StatusNotFound {
			t.Errorf("profile %s: %d, want 404", name, code)
		}
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
