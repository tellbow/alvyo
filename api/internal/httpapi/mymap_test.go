package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
)

// legsRoute is a route of n legs of about 150 m each, heading east from lon0
// at 46.5° N, with the given SAC grade on all of it.
func legsRoute(title string, lon0 float64, n int, sac string) map[string]any {
	anchors := []map[string]any{{"lon": lon0, "lat": 46.5}}
	legs := []map[string]any{}
	for i := range n {
		lon := lon0 + float64(i)*0.002
		legs = append(legs, lineRoute("", "", lon, 46.5, sac)["legs"].([]map[string]any)[0])
		anchors = append(anchors, map[string]any{"lon": lon + 0.002, "lat": 46.5})
	}
	return map[string]any{"title": title, "profile": "hike", "anchors": anchors, "legs": legs}
}

func TestMyMap(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name string) *client {
		c := s.client(t)
		c.do("POST", "/api/v1/auth/signup", signupBody(name+"@example.ch", name))
		if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = $1`, name); err != nil {
			t.Fatal(err)
		}
		return c
	}
	me, other := signup("mapper"), signup("friend")
	create := func(c *client, body map[string]any, tags ...string) string {
		t.Helper()
		body["tags"] = tags
		code, b := c.do("POST", "/api/v1/routes", body)
		if code != http.StatusCreated {
			t.Fatalf("create: %d %s", code, b)
		}
		var r struct{ ID string }
		_ = json.Unmarshal(b, &r)
		return r.ID
	}
	create(me, legsRoute("Kurz", 8.00, 1, "T1"), "Winter")
	create(me, legsRoute("Mittel", 8.01, 3, "T2"), "Tessin")
	create(me, legsRoute("Lang", 8.03, 6, "T4"))
	create(me, legsRoute("Fern", 9.50, 2, "T2"), "Winter") // outside the view
	hike := create(me, legsRoute("Gewandert", 8.06, 2, "T2"))
	if _, err := s.db.Exec(ctx, `UPDATE routes SET hiked_at = now(), hiked_s = 3600 WHERE id = $1`, hike); err != nil {
		t.Fatal(err)
	}
	shared := create(other, legsRoute("Geteilt", 8.08, 1, "T1"), "Winter")
	create(other, legsRoute("Fremd", 8.09, 1, "T1"), "Winter")
	if code, b := other.do("POST", "/api/v1/routes/"+shared+"/grants", map[string]any{"username": "mapper", "role": "viewer"}); code != http.StatusOK {
		t.Fatalf("share: %d %s", code, b)
	}
	// A journey of 2 and 4 legs.
	_, b := me.do("POST", "/api/v1/journeys", map[string]any{"title": "Etappen", "tags": []string{"winter"}})
	jr := "/api/v1/journeys/" + decodeJourney(t, b).ID
	for i, n := range []int{2, 4} {
		_, b = me.do("POST", jr+"/stages", map[string]any{})
		st := decodeJourney(t, b).StageList[i].ID
		body := legsRoute("", 8.10+float64(i)*0.004, n, "T2")
		delete(body, "title")
		if code, b := me.do("POST", jr+"/stages/"+st+"/route", body); code != http.StatusOK {
			t.Fatalf("stage: %d %s", code, b)
		}
	}

	type item struct {
		Kind      string   `json:"kind"`
		Title     string   `json:"title"`
		Tags      []string `json:"tags"`
		DistanceM float64  `json:"distance_m"`
		DurationS int      `json:"duration_s"`
		LongestM  float64  `json:"longest_m"`
		Stages    int      `json:"stages"`
		Lines     [][][2]float64
	}
	get := func(query string) map[string]item {
		t.Helper()
		code, b := me.do("GET", "/api/v1/me/map?bbox=7.9,46.4,8.3,46.6"+query, nil)
		if code != http.StatusOK {
			t.Fatalf("%s: %d %s", query, code, b)
		}
		var r struct{ Items []item }
		_ = json.Unmarshal(b, &r)
		out := map[string]item{}
		for _, it := range r.Items {
			out[it.Title] = it
		}
		return out
	}
	titles := func(m map[string]item) string {
		var ts []string
		for k := range m {
			ts = append(ts, k)
		}
		slices.Sort(ts)
		return strings.Join(ts, ",")
	}

	all := get("")
	if got := titles(all); got != "Etappen,Gewandert,Kurz,Lang,Mittel" {
		t.Fatalf("all: %s", got)
	}
	j := all["Etappen"]
	if all["Gewandert"].Kind != "hike" || all["Kurz"].Kind != "route" || j.Kind != "journey" || j.Stages != 2 ||
		len(j.Lines) != 2 || !slices.Equal(j.Tags, []string{"winter"}) || j.LongestM > j.DistanceM*0.7 {
		t.Errorf("items: %+v", all)
	}
	mittel := all["Mittel"]

	for _, tc := range []struct{ query, want string }{
		{"&kind=hike", "Gewandert"},
		{"&kind=route&kind=journey", "Etappen,Kurz,Lang,Mittel"},
		// Any of the tags, without case.
		{"&tags=WINTER", "Etappen,Kurz"},
		{"&tags=Tessin&tags=winter", "Etappen,Kurz,Mittel"},
		// Ranges with one or two ends; journeys count as a whole unless asked.
		{fmt.Sprintf("&distance_min=%.0f", mittel.DistanceM-1), "Etappen,Lang,Mittel"},
		{fmt.Sprintf("&distance_max=%.0f", mittel.DistanceM+1), "Gewandert,Kurz,Mittel"},
		{fmt.Sprintf("&distance_min=%.0f&distance_max=%.0f", mittel.DistanceM-1, mittel.DistanceM+1), "Mittel"},
		{fmt.Sprintf("&distance_min=%.0f&longest_stage=true", j.LongestM+1), "Lang"},
		{fmt.Sprintf("&duration_max=%d", mittel.DurationS), "Gewandert,Kurz,Mittel"},
		{fmt.Sprintf("&duration_min=%d", mittel.DurationS+1), "Etappen,Lang"},
		{"&sac_min=2&sac_max=3", "Etappen,Gewandert,Mittel"},
		{"&sac_min=4", "Lang"},
		// Combined.
		{"&tags=winter&kind=route&sac_max=1", "Kurz"},
		// Shared with me on request; others' items never.
		{"&shared=true&tags=winter", "Etappen,Geteilt,Kurz"},
	} {
		if got := titles(get(tc.query)); got != tc.want {
			t.Errorf("%s: %s, want %s", tc.query, got, tc.want)
		}
	}

	if code, _ := me.do("GET", "/api/v1/me/map?bbox=8.5,46.4,8.6,46.6", nil); code != http.StatusOK {
		t.Errorf("empty view: %d", code)
	}
	if code, _ := me.do("GET", "/api/v1/me/map?bbox="+url.QueryEscape("8,46,7,47"), nil); code != http.StatusUnprocessableEntity {
		t.Errorf("bad bbox: %d", code)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/me/map?bbox=7.9,46.4,8.3,46.6", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
}
