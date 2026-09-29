package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/bugs"
)

func TestBugReports(t *testing.T) {
	var issue map[string]any
	var auth string
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/tellbow/alvyo/issues" {
			http.NotFound(w, r)
			return
		}
		auth = r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&issue)
		w.WriteHeader(http.StatusCreated)
		_, _ = io.WriteString(w, `{"number": 42, "html_url": "https://github.com/tellbow/alvyo/issues/42"}`)
	}))
	t.Cleanup(gh.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Bugs = &bugs.Store{DB: d.DB, PublicURL: origin, GitHub: &bugs.GitHub{Repo: "tellbow/alvyo", Token: "tok", URL: gh.URL}}
	})
	var shot bytes.Buffer
	_ = png.Encode(&shot, image.NewRGBA(image.Rect(0, 0, 4, 4)))
	report := map[string]any{
		"description": "Die Karte bleibt leer\n@someone schau mal ~~~~",
		"place":       "/routes/0199a000-0000-7000-8000-000000000001",
		"version":     "0.17.0",
		"platform":    "web",
		"screenshot":  shot.Bytes(),
	}

	if code, _ := s.client(t).do("POST", "/api/v1/bug-reports", report); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("hiker@example.ch", "hiker"))
	code, body := c.do("POST", "/api/v1/bug-reports", report)
	var out struct {
		ID       string `json:"id"`
		IssueURL string `json:"issue_url"`
	}
	if err := json.Unmarshal(body, &out); code != http.StatusCreated || err != nil || out.IssueURL == "" {
		t.Fatalf("report: %d %s", code, body)
	}
	text, _ := issue["body"].(string)
	if auth != "Bearer tok" || issue["title"] != "Die Karte bleibt leer" ||
		!strings.Contains(text, "~~~~text\nDie Karte bleibt leer\n@someone schau mal ~~~\n~~~~") ||
		!strings.Contains(text, origin+"/api/v1/bug-reports/"+out.ID+"/screenshot") ||
		!strings.Contains(text, "`hiker`") || !strings.Contains(text, "version `0.17.0`") {
		t.Errorf("issue: %v %v", auth, issue)
	}

	// The screenshot: for moderators only.
	shotPath := "/api/v1/bug-reports/" + out.ID + "/screenshot"
	if code, _ := c.do("GET", shotPath, nil); code != http.StatusForbidden {
		t.Errorf("the reporter: %d", code)
	}
	mod := s.client(t)
	mod.do("POST", "/api/v1/auth/signup", signupBody("mod@example.ch", "mod"))
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET role = 'moderator' WHERE username = 'mod'`); err != nil {
		t.Fatal(err)
	}
	if code, got := mod.do("GET", shotPath, nil); code != http.StatusOK || !bytes.Equal(got, shot.Bytes()) {
		t.Errorf("moderator: %d, %d bytes", code, len(got))
	}

	// Not an image; nothing said.
	report["screenshot"] = []byte("<svg/>")
	if code, _ := c.do("POST", "/api/v1/bug-reports", report); code != http.StatusUnprocessableEntity {
		t.Errorf("svg: %d", code)
	}
	report["screenshot"], report["description"] = nil, "  "
	if code, _ := c.do("POST", "/api/v1/bug-reports", report); code != http.StatusUnprocessableEntity {
		t.Errorf("blank: %d", code)
	}
}
