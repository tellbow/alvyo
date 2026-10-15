package httpapi

import (
	"bytes"
	"context"
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
	var issue, file, comment map[string]any
	var auth, filePath, linked, committed string
	failCommit := false
	comments := 0
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
		case r.Method == http.MethodPost && r.URL.Path == "/repos/tellbow/alvyo/issues/7/comments":
			_ = json.NewDecoder(r.Body).Decode(&comment)
			comments++
			w.WriteHeader(http.StatusCreated)
			_, _ = io.WriteString(w, `{}`)
		case r.Method == http.MethodGet && r.URL.Path == "/repos/tellbow/alvyo/issues":
			// Issue 7 links the screenshot of the report linked, as 1.0 wrote.
			_ = json.NewEncoder(w).Encode([]map[string]any{
				{"number": 3, "body": "something else"},
				{"number": 7, "body": "- Screenshot (moderators, signed in): " + origin + "/api/v1/bug-reports/" + linked + "/screenshot\n"},
			})
		case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/repos/tellbow/alvyo/contents/"):
			p := strings.TrimPrefix(r.URL.Path, "/repos/tellbow/alvyo/contents/")
			if committed == "" || !strings.Contains(p, committed) {
				http.NotFound(w, r)
				return
			}
			_, _ = io.WriteString(w, `{"html_url": "https://github.com/tellbow/alvyo/blob/main/`+p+`"}`)
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

	// The screenshot: committed to the repository, shown in the issue, not
	// kept in the database.
	if !strings.HasPrefix(filePath, "screenshots/") || !strings.HasSuffix(filePath, "/"+out.ID+".png") ||
		file["content"] != base64.StdEncoding.EncodeToString(shot.Bytes()) {
		t.Errorf("commit: %s %v", filePath, file)
	}
	if !strings.Contains(text, "![Screenshot](https://github.com/tellbow/alvyo/blob/main/"+filePath+"?raw=true)") {
		t.Errorf("issue without the screenshot: %s", text)
	}
	var kept int
	if err := s.db.QueryRow(context.Background(), `SELECT count(*) FROM bug_reports WHERE screenshot IS NOT NULL`).Scan(&kept); err != nil || kept != 0 {
		t.Errorf("screenshots in the database: %d %v", kept, err)
	}

	// GitHub takes the issue but not the screenshot: the issue says so.
	failCommit = true
	code, body = c.do("POST", "/api/v1/bug-reports", report)
	var second struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(body, &second); code != http.StatusCreated ||
		!strings.Contains(issue["body"].(string), "- Screenshot: could not be stored") {
		t.Errorf("commit failed: %d %s %v %v", code, body, issue, err)
	}
	failCommit = false

	// Kept by an earlier version: one moves to the issue that links it,
	// not to the number stored (the issues moved to another repository and
	// were numbered anew); one an earlier run committed, linked by no issue,
	// is only dropped from the database.
	ctx := context.Background()
	for _, r := range []struct {
		id     string
		number int
	}{{out.ID, 3}, {second.ID, 7}} {
		if _, err := s.db.Exec(ctx, `UPDATE bug_reports SET screenshot = $2, screenshot_type = 'image/png', issue_number = $3 WHERE id = $1`,
			r.id, shot.Bytes(), r.number); err != nil {
			t.Fatal(err)
		}
	}
	linked, committed, filePath = out.ID, second.ID, ""
	n, err := (&bugs.Store{DB: s.db, GitHub: github}).MoveScreenshots(ctx)
	if err != nil || n != 2 || !strings.HasSuffix(filePath, "/"+out.ID+".png") || comments != 1 ||
		comment["body"] != "![Screenshot](https://github.com/tellbow/alvyo/blob/main/"+filePath+"?raw=true)\n" {
		t.Errorf("move: %d %v %s %d %v", n, err, filePath, comments, comment)
	}
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM bug_reports WHERE screenshot IS NOT NULL OR screenshot_type IS NOT NULL`).Scan(&kept); err != nil || kept != 0 {
		t.Errorf("screenshots left after the move: %d %v", kept, err)
	}

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
