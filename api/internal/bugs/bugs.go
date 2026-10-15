// Package bugs keeps bug reports from the website and the app and opens
// each as an issue on GitHub. The screenshot is committed to the same
// (private) repository and shown in the issue.
package bugs

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MaxScreenshotBytes bounds a screenshot (PNG or JPEG).
const MaxScreenshotBytes = 4 << 20

// ErrScreenshot means the screenshot is not a PNG or JPEG.
var ErrScreenshot = errors.New("bugs: screenshot must be PNG or JPEG")

// Report is what the reporter sends, and who they are.
type Report struct {
	UserID      uuid.UUID
	Username    string
	Description string
	Place       string // the page's address or the app's screen, and the item
	Version     string
	Platform    string // web, ios or android
	Screenshot  []byte
}

// Store keeps reports; GitHub opens their issues (nil: kept only).
type Store struct {
	DB     *pgxpool.Pool
	GitHub *GitHub
}

// Create keeps a report and opens its issue; the issue's address, empty
// when GitHub is not configured or did not answer (the report is kept).
func (s *Store) Create(ctx context.Context, r Report) (id uuid.UUID, issueURL string, err error) {
	r.Place, r.Version = Place(r.Place), oneLine(r.Version)
	if len(r.Screenshot) > 0 {
		if _, ok := screenshotExt(r.Screenshot); !ok {
			return uuid.Nil, "", ErrScreenshot
		}
	}
	if err := s.DB.QueryRow(ctx, `
		INSERT INTO bug_reports (user_id, description, place, version, platform)
		VALUES ($1, $2, $3, $4, $5) RETURNING id`,
		r.UserID, r.Description, r.Place, r.Version, r.Platform).Scan(&id); err != nil {
		return uuid.Nil, "", fmt.Errorf("bugs: create: %w", err)
	}
	if s.GitHub == nil {
		return id, "", nil // the screenshot has nowhere to go
	}
	screenshot := Screenshot{}
	if len(r.Screenshot) > 0 {
		if screenshot.URL, err = s.GitHub.Commit(ctx, screenshotPath(id, r.Screenshot), r.Screenshot); err != nil {
			slog.WarnContext(ctx, "bug report: screenshot not stored", "id", id, "err", err)
			screenshot.Failed = true
		}
	}
	number, url, err := s.GitHub.Open(ctx, Title(r.Description), Body(r, screenshot))
	if err != nil {
		slog.WarnContext(ctx, "bug report: no issue", "id", id, "err", err)
		return id, "", nil
	}
	if _, err := s.DB.Exec(ctx, `UPDATE bug_reports SET issue_number = $2 WHERE id = $1`, id, number); err != nil {
		return id, url, fmt.Errorf("bugs: issue number: %w", err)
	}
	return id, url, nil
}

// MoveScreenshots commits the screenshots that earlier versions kept in
// the database, shows each in a comment on its issue and drops it from
// the database; how many it moved. The issue is the one whose text links
// the report's screenshot: the stored numbers changed when the issues
// moved to another repository. Without one the file is only committed.
func (s *Store) MoveScreenshots(ctx context.Context) (int, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, screenshot FROM bug_reports WHERE screenshot IS NOT NULL ORDER BY id`)
	if err != nil {
		return 0, fmt.Errorf("bugs: screenshots: %w", err)
	}
	type old struct {
		id   uuid.UUID
		shot []byte
	}
	olds, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (old, error) {
		var o old
		err := r.Scan(&o.id, &o.shot)
		return o, err
	})
	if err != nil {
		return 0, fmt.Errorf("bugs: screenshots: %w", err)
	}
	issues, err := s.GitHub.reportIssues(ctx)
	if err != nil {
		return 0, err
	}
	for i, o := range olds {
		path := screenshotPath(o.id, o.shot)
		// Committed by an earlier run that stopped before the comment.
		url, err := s.GitHub.File(ctx, path)
		if err == nil && url == "" {
			url, err = s.GitHub.Commit(ctx, path, o.shot)
		}
		if err != nil {
			return i, err
		}
		if number, ok := issues[o.id]; ok {
			if err := s.GitHub.Comment(ctx, number, screenshotMarkdown(url)+"\n"); err != nil {
				return i, err
			}
		}
		if _, err := s.DB.Exec(ctx, `UPDATE bug_reports SET screenshot = NULL, screenshot_type = NULL WHERE id = $1`, o.id); err != nil {
			return i, fmt.Errorf("bugs: screenshots: %w", err)
		}
	}
	return len(olds), nil
}

// screenshotExt is the file extension of a PNG or JPEG.
func screenshotExt(b []byte) (string, bool) {
	switch http.DetectContentType(b) {
	case "image/png":
		return "png", true
	case "image/jpeg":
		return "jpg", true
	}
	return "", false
}

// screenshotPath is where a report's screenshot goes in the repository:
// by month, named after the report.
func screenshotPath(id uuid.UUID, b []byte) string {
	ext, _ := screenshotExt(b)
	return fmt.Sprintf("screenshots/%s/%s.%s", time.Unix(id.Time().UnixTime()).UTC().Format("2006-01"), id, ext)
}

// screenshotMarkdown shows a committed screenshot: ?raw=true serves the
// image itself, also from a private repository to those who can see it.
func screenshotMarkdown(url string) string {
	return "![Screenshot](" + url + "?raw=true)"
}

// secretPath matches the part of an address that is a token: live
// locations and friend invites carry it in the path.
var secretPath = regexp.MustCompile(`/(live|friends/invite|friend-invites)/[^/?#]+`)

// Place is the reported address without what would let a reader of the
// issue in: path tokens masked, share and reset tokens dropped, and
// on one line, so it cannot add markdown to the issue.
func Place(place string) string {
	place = oneLine(place)
	path, query, _ := strings.Cut(place, "?")
	path = secretPath.ReplaceAllString(path, "/$1/-")
	if q, err := url.ParseQuery(query); err == nil && query != "" {
		q.Del("t")
		q.Del("token")
		if query = q.Encode(); query != "" {
			return path + "?" + query
		}
		return path
	}
	return path
}

// oneLine replaces control characters (line breaks among them) by spaces.
func oneLine(s string) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, s)
}

// Title is the description's first line, at most 80 characters.
func Title(description string) string {
	line, _, _ := strings.Cut(strings.TrimSpace(description), "\n")
	line = strings.TrimSpace(line)
	if utf8.RuneCountInString(line) > 80 {
		line = string([]rune(line)[:79]) + "…"
	}
	return line
}

// Screenshot is what became of a report's screenshot: its address in the
// repository, or Failed.
type Screenshot struct {
	URL    string
	Failed bool
}

// Body is the issue's text: the description as it was written (in a
// fence, so it mentions and formats nothing), where it happened, the
// version and the screenshot.
func Body(r Report, screenshot Screenshot) string {
	var b strings.Builder
	b.WriteString("~~~~text\n")
	b.WriteString(strings.ReplaceAll(strings.TrimSpace(r.Description), "~~~~", "~~~"))
	b.WriteString("\n~~~~\n\n")
	fmt.Fprintf(&b, "- Where: `%s`\n", strings.ReplaceAll(r.Place, "`", "'"))
	fmt.Fprintf(&b, "- Platform: %s, version `%s`\n", r.Platform, strings.ReplaceAll(r.Version, "`", "'"))
	fmt.Fprintf(&b, "- Reported by: `%s`\n", r.Username)
	switch {
	case screenshot.Failed:
		b.WriteString("- Screenshot: could not be stored\n")
	case screenshot.URL != "":
		b.WriteString("\n" + screenshotMarkdown(screenshot.URL) + "\n")
	}
	b.WriteString("\n_Sent with «Fehler melden»._\n")
	return b.String()
}

// GitHub opens issues in Repo ("owner/name") and commits screenshots to
// it, with a token that may write its issues and contents.
type GitHub struct {
	Repo   string
	Token  string
	URL    string // defaults to https://api.github.com
	Client *http.Client
}

// Open opens an issue labelled bug; its number and address.
func (g *GitHub) Open(ctx context.Context, title, body string) (int, string, error) {
	var out struct {
		Number  int    `json:"number"`
		HTMLURL string `json:"html_url"`
	}
	err := g.do(ctx, http.MethodPost, "/issues", map[string]any{"title": title, "body": body, "labels": []string{"bug"}}, &out)
	return out.Number, out.HTMLURL, err
}

// Commit adds a file at path to the repository's default branch; its
// address on github.com.
func (g *GitHub) Commit(ctx context.Context, path string, content []byte) (string, error) {
	var out struct {
		Content struct {
			HTMLURL string `json:"html_url"`
		} `json:"content"`
	}
	if err := g.do(ctx, http.MethodPut, "/contents/"+path, map[string]any{
		"message": "Screenshot for a bug report",
		"content": base64.StdEncoding.EncodeToString(content),
	}, &out); err != nil {
		return "", err
	}
	if out.Content.HTMLURL == "" {
		return "", errors.New("github: no address for the file")
	}
	return out.Content.HTMLURL, nil
}

// File is the address of the file at path on github.com; empty when
// there is none.
func (g *GitHub) File(ctx context.Context, path string) (string, error) {
	var out struct {
		HTMLURL string `json:"html_url"`
	}
	err := g.do(ctx, http.MethodGet, "/contents/"+path, nil, &out)
	if s, ok := errors.AsType[statusError](err); ok && s.code == http.StatusNotFound {
		return "", nil
	}
	return out.HTMLURL, err
}

// reportLink finds a report in an issue's text: the link to its
// screenshot that versions up to 1.0 wrote.
var reportLink = regexp.MustCompile(`/bug-reports/([0-9a-f-]{36})/screenshot`)

// reportIssues are the numbers of the issues that link a report's
// screenshot, by report.
func (g *GitHub) reportIssues(ctx context.Context) (map[uuid.UUID]int, error) {
	out := map[uuid.UUID]int{}
	for page := 1; ; page++ {
		var issues []struct {
			Number int    `json:"number"`
			Body   string `json:"body"`
		}
		if err := g.do(ctx, http.MethodGet, fmt.Sprintf("/issues?state=all&per_page=100&page=%d", page), nil, &issues); err != nil {
			return nil, err
		}
		for _, i := range issues {
			for _, m := range reportLink.FindAllStringSubmatch(i.Body, -1) {
				if id, err := uuid.Parse(m[1]); err == nil {
					out[id] = i.Number
				}
			}
		}
		if len(issues) < 100 {
			return out, nil
		}
	}
}

// Comment adds a comment to issue number.
func (g *GitHub) Comment(ctx context.Context, number int, body string) error {
	return g.do(ctx, http.MethodPost, fmt.Sprintf("/issues/%d/comments", number), map[string]any{"body": body}, nil)
}

// statusError is an answer other than 200 or 201.
type statusError struct {
	code int
	msg  string
}

func (e statusError) Error() string { return fmt.Sprintf("status %d: %s", e.code, e.msg) }

// do sends payload (none when nil) to the repository's endpoint path and
// decodes the answer into out.
func (g *GitHub) do(ctx context.Context, method, path string, payload, out any) error {
	var body io.Reader
	if payload != nil {
		b, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(b)
	}
	base := g.URL
	if base == "" {
		base = "https://api.github.com"
	}
	req, err := http.NewRequestWithContext(ctx, method, base+"/repos/"+g.Repo+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+g.Token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("github: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("github: %s %s: %w", method, path, statusError{resp.StatusCode, string(msg)})
	}
	if out == nil {
		return nil
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("github: %w", err)
	}
	return nil
}
