package httpapi

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

func TestJourneyReminders(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("walker@example.ch", "walker"))
	_, body := c.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina"})
	base := "/api/v1/journeys/" + decodeJourney(t, body).ID
	c.do("POST", base+"/stages", map[string]any{})
	_, body = c.do("GET", base, nil)
	st := decodeJourney(t, body).StageList[0].ID
	start := time.Now().AddDate(0, 0, 30).Format(time.DateOnly)
	c.do("PATCH", base+"/stages/"+st, map[string]any{"planned_date": start}, stageMatch(t, c, base, st)...)

	type answer struct {
		On       bool   `json:"on"`
		Start    string `json:"start"`
		Upcoming []struct {
			Kind string `json:"kind"`
			Day  string `json:"day"`
		} `json:"upcoming"`
	}
	decode := func(code int, body []byte) answer {
		t.Helper()
		var a answer
		if err := json.Unmarshal(body, &a); code != http.StatusOK || err != nil {
			t.Fatalf("reminders: %d %s", code, body)
		}
		return a
	}
	a := decode(c.do("GET", base+"/reminders", nil))
	if !a.On || a.Start != start || len(a.Upcoming) != 3 || a.Upcoming[0].Kind != "book" ||
		a.Upcoming[0].Day != time.Now().AddDate(0, 0, 9).Format(time.DateOnly) {
		t.Errorf("reminders: %+v", a)
	}
	if a = decode(c.do("PUT", base+"/reminders", map[string]any{"on": false})); a.On {
		t.Errorf("off: %+v", a)
	}
	if a = decode(c.do("GET", base+"/reminders", nil)); a.On {
		t.Errorf("kept off: %+v", a)
	}
	if code, _ := s.client(t).do("GET", base+"/reminders", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	other := s.client(t)
	other.do("POST", "/api/v1/auth/signup", signupBody("nosy@example.ch", "nosy"))
	if code, _ := other.do("PUT", base+"/reminders", map[string]any{"on": false}); code != http.StatusNotFound {
		t.Errorf("someone else's private journey: %d", code)
	}
}
