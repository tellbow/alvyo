package httpapi

import (
	"encoding/json"
	"net/http"
	"reflect"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/tags"
)

func TestTags(t *testing.T) {
	s := newTestServer(t, Limits{})
	owner, other := s.client(t), s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("tagger@example.ch", "tagger"))
	other.do("POST", "/api/v1/auth/signup", signupBody("other@example.ch", "other"))
	if code, _ := s.client(t).do("GET", "/api/v1/me/tags", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous tag list: %d", code)
	}

	type tagged struct {
		ID      string   `json:"id"`
		Version int      `json:"version"`
		Tags    []string `json:"tags"`
	}
	decode := func(code int, body []byte, want int) tagged {
		t.Helper()
		if code != want {
			t.Fatalf("%d, want %d: %s", code, want, body)
		}
		var v tagged
		_ = json.Unmarshal(body, &v)
		return v
	}
	withTags := func(body map[string]any, tags ...string) map[string]any {
		body["tags"] = tags
		return body
	}

	// Normalised on the way in: trimmed, repeats without case dropped.
	code, body := owner.do("POST", "/api/v1/routes", withTags(newRouteBody("Gratweg", "private"), " Winter ", "mit   Kindern", "winter"))
	r := decode(code, body, http.StatusCreated)
	if !reflect.DeepEqual(r.Tags, []string{"Winter", "mit Kindern"}) {
		t.Errorf("route tags %q", r.Tags)
	}
	routePath := "/api/v1/routes/" + r.ID
	code, body = owner.do("POST", "/api/v1/routes", withTags(newRouteBody("Seeweg", "private"), "Winter", "Tessin"))
	decode(code, body, http.StatusCreated)
	code, body = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "tags": []string{"Tessin", "Winter"}})
	j := decode(code, body, http.StatusCreated)
	code, body = owner.do("POST", "/api/v1/collections", map[string]any{"title": "Später", "tags": []string{"Wunschliste"}})
	c := decode(code, body, http.StatusCreated)
	if !reflect.DeepEqual(j.Tags, []string{"Tessin", "Winter"}) || !reflect.DeepEqual(c.Tags, []string{"Wunschliste"}) {
		t.Errorf("journey %q, collection %q", j.Tags, c.Tags)
	}

	// Replaced by a change that sends them, kept by one that does not.
	code, body = owner.do("PATCH", routePath, map[string]any{"tags": []string{"tessin"}}, "If-Match", `"1"`)
	if r = decode(code, body, http.StatusOK); !reflect.DeepEqual(r.Tags, []string{"tessin"}) {
		t.Errorf("replaced: %q", r.Tags)
	}
	code, body = owner.do("PATCH", routePath, map[string]any{"title": "Grat"}, "If-Match", `"2"`)
	if r = decode(code, body, http.StatusOK); !reflect.DeepEqual(r.Tags, []string{"tessin"}) {
		t.Errorf("kept: %q", r.Tags)
	}
	code, body = owner.do("PATCH", "/api/v1/collections/"+c.ID, map[string]any{"tags": []string{}}, "If-Match", `"1"`)
	if c = decode(code, body, http.StatusOK); c.Tags == nil || len(c.Tags) != 0 {
		t.Errorf("removed: %#v", c.Tags)
	}
	code, body = owner.do("PATCH", "/api/v1/journeys/"+j.ID, map[string]any{"tags": []string{"Tessin", "Winter", "Hütten"}}, "If-Match", `"1"`)
	decode(code, body, http.StatusOK)

	// Limits.
	many := make([]string, 21)
	for i := range many {
		many[i] = strings.Repeat("x", i+1)
	}
	for _, bad := range [][]string{many, {strings.Repeat("ä", 41)}} {
		if code, body := owner.do("PATCH", routePath, map[string]any{"tags": bad}, "If-Match", `"3"`); code != http.StatusUnprocessableEntity {
			t.Errorf("%d tags: %d %s", len(bad), code, body)
		}
	}

	// A stage route shows its journey's tags and takes none of its own.
	_, body = owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages", map[string]any{})
	stage := decodeJourney(t, body).StageList[0].ID
	_, body = owner.do("POST", "/api/v1/journeys/"+j.ID+"/stages/"+stage+"/route", stageRouteBody(8.0))
	stagePath := "/api/v1/routes/" + decodeJourney(t, body).StageList[0].Route.ID
	code, body = owner.do("GET", stagePath, nil)
	if sr := decode(code, body, http.StatusOK); !reflect.DeepEqual(sr.Tags, []string{"Tessin", "Winter", "Hütten"}) {
		t.Errorf("stage route tags %q", sr.Tags)
	}
	if code, _ := owner.do("PATCH", stagePath, map[string]any{"tags": []string{"x"}}, "If-Match", `"1"`); code != http.StatusUnprocessableEntity {
		t.Errorf("stage route own tags: %d", code)
	}

	// Lists carry them.
	_, body = owner.do("GET", "/api/v1/routes", nil)
	if !strings.Contains(string(body), `"tags":["tessin"]`) {
		t.Errorf("route list: %s", body)
	}

	// The user's tags with counts, ignoring case (the spelling used most
	// wins); only their own.
	other.do("POST", "/api/v1/routes", withTags(newRouteBody("Fremd", "private"), "Winter", "Velo"))
	_, body = owner.do("GET", "/api/v1/me/tags", nil)
	var list struct {
		Tags []tags.Count `json:"tags"`
	}
	_ = json.Unmarshal(body, &list)
	want := []tags.Count{{Tag: "Tessin", Count: 3}, {Tag: "Winter", Count: 2}, {Tag: "Hütten", Count: 1}}
	if !reflect.DeepEqual(list.Tags, want) {
		t.Errorf("tag list %+v, want %+v", list.Tags, want)
	}
}
