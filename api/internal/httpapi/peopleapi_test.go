package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

func TestJourneyPeople(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	owner := s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("walker@example.ch", "walker"))
	anna := s.client(t)
	anna.do("POST", "/api/v1/auth/signup", signupBody("anna@example.ch", "anna"))
	editor := s.client(t)
	editor.do("POST", "/api/v1/auth/signup", signupBody("beat@example.ch", "beat"))
	stranger := s.client(t)
	stranger.do("POST", "/api/v1/auth/signup", signupBody("nosy@example.ch", "nosy"))
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}

	_, body := owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "public"})
	base := "/api/v1/journeys/" + decodeJourney(t, body).ID
	for range 3 {
		owner.do("POST", base+"/stages", map[string]any{})
	}
	_, body = owner.do("GET", base, nil)
	j := decodeJourney(t, body)
	s1, s2, s3 := j.StageList[0].ID, j.StageList[1].ID, j.StageList[2].ID
	owner.do("POST", base+"/grants", map[string]any{"username": "beat", "role": "editor"})

	type people struct {
		People []struct {
			ID          string   `json:"id"`
			Username    string   `json:"username"`
			DisplayName string   `json:"display_name"`
			Email       string   `json:"email"`
			Stages      []string `json:"stages"`
		} `json:"people"`
	}
	decode := func(code int, body []byte) people {
		t.Helper()
		var p people
		if err := json.Unmarshal(body, &p); code != http.StatusOK || err != nil {
			t.Fatalf("people: %d %s", code, body)
		}
		return p
	}

	// Anna on all stages, the editor on two (keeping their role), someone by address on one.
	decode(owner.do("POST", base+"/people", map[string]any{"username": "anna"}))
	decode(owner.do("POST", base+"/people", map[string]any{"username": "beat", "stages": []string{s1, s3}}))
	p := decode(owner.do("POST", base+"/people", map[string]any{"email": "carla@example.ch", "stages": []string{s2}}))
	// In the order they got access: Beat was shared with before.
	if len(p.People) != 3 || p.People[0].Username != "beat" || len(p.People[0].Stages) != 2 ||
		p.People[1].Username != "anna" || len(p.People[1].Stages) != 3 || p.People[2].Email != "carla@example.ch" {
		t.Fatalf("added: %+v", p)
	}
	invited := false
	for _, m := range s.mail.Sent() {
		invited = invited || m.To == "carla@example.ch"
	}
	if !invited {
		t.Error("carla not invited")
	}
	var role string
	if err := s.db.QueryRow(ctx, `SELECT g.role::text FROM grants g JOIN users u ON u.id = g.user_id WHERE u.username = 'beat'`).Scan(&role); err != nil {
		t.Fatal(err)
	}
	if role != "editor" {
		t.Errorf("the editor became a %s", role)
	}

	// Those it is shared with see who comes along, without addresses; the public does not.
	p = decode(anna.do("GET", base+"/people", nil))
	if len(p.People) != 3 || p.People[2].Email != "" {
		t.Errorf("anna sees: %+v", p)
	}
	if code, _ := stranger.do("GET", base+"/people", nil); code != http.StatusForbidden {
		t.Errorf("a stranger on a public journey: %d", code)
	}
	if code, _ := s.client(t).do("GET", base+"/people", nil); code != http.StatusForbidden {
		t.Errorf("anonymous: %d", code)
	}

	// The editor moves Anna to the first stage; only the owner adds and removes.
	annaID := p.People[1].ID
	p = decode(editor.do("PUT", base+"/people/"+annaID, map[string]any{"stages": []string{s1}}))
	if len(p.People[1].Stages) != 1 || p.People[1].Stages[0] != s1 {
		t.Errorf("anna's stages: %+v", p.People[1])
	}
	if code, _ := editor.do("POST", base+"/people", map[string]any{"username": "nosy"}); code != http.StatusForbidden {
		t.Errorf("an editor adds: %d", code)
	}
	if code, _ := anna.do("PUT", base+"/people/"+annaID, map[string]any{"stages": []string{}}); code != http.StatusForbidden {
		t.Errorf("a viewer changes: %d", code)
	}
	p = decode(owner.do("DELETE", base+"/people/"+annaID, nil))
	if len(p.People) != 2 {
		t.Errorf("removed: %+v", p)
	}
	// Anna keeps seeing the journey.
	if code, _ := anna.do("GET", base+"/people", nil); code != http.StatusOK {
		t.Errorf("anna after: %d", code)
	}
	if code, _ := owner.do("PUT", base+"/people/"+annaID, map[string]any{"stages": []string{s1}}); code != http.StatusNotFound {
		t.Errorf("not along any more: %d", code)
	}
	// A deleted stage leaves its people.
	owner.do("DELETE", base+"/stages/"+s3, nil, stageMatch(t, owner, base, s3)...)
	p = decode(owner.do("GET", base+"/people", nil))
	if len(p.People[0].Stages) != 1 {
		t.Errorf("after deleting a stage: %+v", p.People[0])
	}
}
