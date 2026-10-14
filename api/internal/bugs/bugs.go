// Package bugs keeps bug reports from the website and the app and opens
// each as an issue on GitHub. The screenshot stays in the database: the
// issue links to it for moderators, and it goes with the account.
package bugs

import (
	"bytes"
	"context"
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

// ErrNotFound means no such report, or one without a screenshot.
var ErrNotFound = errors.New("bugs: not found")

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
	DB        *pgxpool.Pool
	GitHub    *GitHub
	PublicURL string
}

// Create keeps a report and opens its issue; the issue's address, empty
// when GitHub is not configured or did not answer (the report is kept).
func (s *Store) Create(ctx context.Context, r Report) (id uuid.UUID, issueURL string, err error) {
	r.Place, r.Version = Place(r.Place), oneLine(r.Version)
	var kind *string
	if len(r.Screenshot) > 0 {
		t := http.DetectContentType(r.Screenshot)
		if t != "image/png" && t != "image/jpeg" {
			return uuid.Nil, "", ErrScreenshot
		}
		kind = &t
	}
	var shot []byte
	if kind != nil {
		shot = r.Screenshot
	}
	if err := s.DB.QueryRow(ctx, `
		INSERT INTO bug_reports (user_id, description, place, version, platform, screenshot, screenshot_type)
		VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
		r.UserID, r.Description, r.Place, r.Version, r.Platform, shot, kind).Scan(&id); err != nil {
		return uuid.Nil, "", fmt.Errorf("bugs: create: %w", err)
	}
	if s.GitHub == nil {
		return id, "", nil
	}
	screenshot := ""
	if kind != nil {
		screenshot = s.PublicURL + "/api/v1/bug-reports/" + id.String() + "/screenshot"
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

// Screenshot returns a report's screenshot and its type.
func (s *Store) Screenshot(ctx context.Context, id uuid.UUID) ([]byte, string, error) {
	var b []byte
	var t *string
	err := s.DB.QueryRow(ctx, `SELECT screenshot, screenshot_type FROM bug_reports WHERE id = $1`, id).Scan(&b, &t)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && (b == nil || t == nil)) {
		return nil, "", ErrNotFound
	}
	if err != nil {
		return nil, "", fmt.Errorf("bugs: screenshot: %w", err)
	}
	return b, *t, nil
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

// Body is the issue's text: the description as it was written (in a
// fence, so it mentions and formats nothing), where it happened, the
// version and the screenshot's link.
func Body(r Report, screenshot string) string {
	var b strings.Builder
	b.WriteString("~~~~text\n")
	b.WriteString(strings.ReplaceAll(strings.TrimSpace(r.Description), "~~~~", "~~~"))
	b.WriteString("\n~~~~\n\n")
	fmt.Fprintf(&b, "- Where: `%s`\n", strings.ReplaceAll(r.Place, "`", "'"))
	fmt.Fprintf(&b, "- Platform: %s, version `%s`\n", r.Platform, strings.ReplaceAll(r.Version, "`", "'"))
	fmt.Fprintf(&b, "- Reported by: `%s`\n", r.Username)
	if screenshot != "" {
		fmt.Fprintf(&b, "- Screenshot (moderators, signed in): %s\n", screenshot)
	}
	b.WriteString("\n_Sent with «Fehler melden»._\n")
	return b.String()
}

// GitHub opens issues in Repo ("owner/name") with a token that may write
// its issues.
type GitHub struct {
	Repo   string
	Token  string
	URL    string // defaults to https://api.github.com
	Client *http.Client
}

// Open opens an issue labelled bug; its number and address.
func (g *GitHub) Open(ctx context.Context, title, body string) (int, string, error) {
	payload, _ := json.Marshal(map[string]any{"title": title, "body": body, "labels": []string{"bug"}})
	base := g.URL
	if base == "" {
		base = "https://api.github.com"
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/repos/"+g.Repo+"/issues", bytes.NewReader(payload))
	if err != nil {
		return 0, "", err
	}
	req.Header.Set("Authorization", "Bearer "+g.Token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return 0, "", fmt.Errorf("github: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusCreated {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return 0, "", fmt.Errorf("github: status %d: %s", resp.StatusCode, msg)
	}
	var out struct {
		Number  int    `json:"number"`
		HTMLURL string `json:"html_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return 0, "", fmt.Errorf("github: %w", err)
	}
	return out.Number, out.HTMLURL, nil
}
