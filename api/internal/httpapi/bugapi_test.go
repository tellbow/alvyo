package httpapi

import (
	"bytes"
	"encoding/base64"
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
	var issue, file map[string]any
	var auth, filePath string
	failCommit := false
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/repos/tellbow/alvyo/issues":
			_ = json.NewDecoder(r.Body).Decode(&issue)
			w.WriteHeader(http.StatusCreated)
			_, _ = io.WriteString(w, `{"number": 42, "html_url": "https://github.com/tellbow/alvyo/issues/42"}`)
		case r.Method == http.MethodPut && strings.HasPrefix(r.URL.Path, "/repos/tellbow/alvyo/contents/") && !failCommit:
			filePath = strings.TrimPrefix(r.URL.Path, "/repos/tellbow/alvyo/contents/")
			_ = json.NewDecoder(r.Body).Decode(&file)
			w.WriteHeader(http.StatusCreated)
			_, _ = io.WriteString(w, `{"content": {"html_url": "https://github.com/tellbow/alvyo/blob/main/`+filePath+`"}}`)
		default:
			http.Error(w, "no", http.StatusForbidden)
		}
	}))
	t.Cleanup(gh.Close)
	github := &bugs.GitHub{Repo: "tellbow/alvyo", Token: "tok", URL: gh.URL}
	s := newTestServerWith(t, func(d *Deps) {
		d.Bugs = &bugs.Store{DB: d.DB, GitHub: github}
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
	s.signup(c, "hiker@example.ch", "hiker")
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
		!strings.Contains(text, "`hiker`") || !strings.Contains(text, "version `0.17.0`") {
		t.Errorf("issue: %v %v", auth, issue)
	}

	// The screenshot: committed to the repository, shown in the issue.
	if !strings.HasPrefix(filePath, "screenshots/") || !strings.HasSuffix(filePath, "/"+out.ID+".png") ||
		file["content"] != base64.StdEncoding.EncodeToString(shot.Bytes()) {
		t.Errorf("commit: %s %v", filePath, file)
	}
	if !strings.Contains(text, "![Screenshot](https://github.com/tellbow/alvyo/blob/main/"+filePath+"?raw=true)") {
		t.Errorf("issue without the screenshot: %s", text)
	}

	// GitHub takes the issue but not the screenshot: the issue says so.
	failCommit = true
	if code, body := c.do("POST", "/api/v1/bug-reports", report); code != http.StatusCreated ||
		!strings.Contains(issue["body"].(string), "- Screenshot: could not be stored") {
		t.Errorf("commit failed: %d %s %v", code, body, issue)
	}
	failCommit = false

	// From the Android app.
	report["platform"] = "android"
	if code, body := c.do("POST", "/api/v1/bug-reports", report); code != http.StatusCreated ||
		!strings.Contains(issue["body"].(string), "Platform: android") {
		t.Errorf("android: %d %s", code, body)
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
