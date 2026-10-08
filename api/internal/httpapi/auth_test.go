package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/discover"
	"github.com/tellbow/alvyo/api/internal/done"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/places"
	"github.com/tellbow/alvyo/api/internal/precip"
	"github.com/tellbow/alvyo/api/internal/ratelimit"
	"github.com/tellbow/alvyo/api/internal/reminders"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/api/internal/travel"
)

const origin = "http://alvyo.test"

type testServer struct {
	*httptest.Server
	mail *mailer.Recorder
	db   *pgxpool.Pool
}

func newTestServer(t *testing.T, limits Limits) *testServer {
	t.Helper()
	return newTestServerWith(t, func(d *Deps) { d.Limits = limits })
}

// newTestServerWith lets a test adjust the dependencies (fakes, limits).
func newTestServerWith(t *testing.T, adjust func(*Deps)) *testServer {
	t.Helper()
	pool := testdb.New(t)
	rec := &mailer.Recorder{}
	wa, err := auth.NewWebAuthn(origin)
	if err != nil {
		t.Fatal(err)
	}
	d := Deps{
		DB:          pool,
		Auth:        &auth.Service{DB: pool, Mail: rec, PublicURL: origin, WebAuthn: wa},
		Routes:      &routes.Store{DB: pool},
		Journeys:    &journeys.Store{DB: pool, Routes: &routes.Store{DB: pool}},
		Places:      &places.Store{DB: pool},
		Grants:      &grants.Store{DB: pool, Mail: rec, PublicURL: origin},
		Collections: &collections.Store{DB: pool},
		Precip:      &precip.Store{DB: pool},
		Discover:    &discover.Store{DB: pool},
		Community:   &community.Store{DB: pool, Mail: rec, PublicURL: origin},
		Done:        &done.Store{DB: pool},
		Photos:      &photos.Store{DB: pool, Files: &photos.Files{Dir: t.TempDir()}},
		Travel:      &travel.Store{DB: pool},
		Reminders:   &reminders.Store{DB: pool, Mail: rec, PublicURL: origin},
		Version:     "test",
		PublicURL:   origin,
	}
	adjust(&d)
	h, _ := New(d)
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &testServer{Server: srv, mail: rec, db: pool}
}

// client is a browser-like client with a cookie jar that sends our Origin.
type client struct {
	t    *testing.T
	base string
	http *http.Client
}

func (s *testServer) client(t *testing.T) *client {
	jar, _ := cookiejar.New(nil)
	return &client{t: t, base: s.URL, http: &http.Client{Jar: jar}}
}

func (c *client) do(method, path string, body any, headers ...string) (int, []byte) {
	c.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+path, r)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", origin)
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	resp, err := c.http.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	out, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, out
}

var mailToken = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

func signupBody(email, username string) map[string]any {
	return map[string]any{"email": email, "username": username, "display_name": "Test User", "password": "sehr-geheim-123", "locale": "de"}
}

func TestAuthFlow(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)

	code, body := c.do("POST", "/api/v1/auth/signup", signupBody("anna@example.ch", "anna"))
	if code != http.StatusCreated {
		t.Fatalf("signup: %d %s", code, body)
	}
	var me struct {
		User Me `json:"user"`
	}
	_ = json.Unmarshal(body, &me)
	if me.User.Username != "anna" || me.User.EmailVerified {
		t.Errorf("signup user: %+v", me.User)
	}

	// Signed up = logged in.
	if code, body := c.do("GET", "/api/v1/me", nil); code != http.StatusOK {
		t.Fatalf("me after signup: %d %s", code, body)
	}

	// Verification e-mail → verify.
	msgs := s.mail.Sent()
	if len(msgs) != 1 || msgs[0].To != "anna@example.ch" {
		t.Fatalf("mails: %+v", msgs)
	}
	token := mailToken.FindStringSubmatch(msgs[0].Text)[1]
	if code, body := c.do("POST", "/api/v1/auth/verify-email", map[string]any{"token": token}); code != http.StatusNoContent {
		t.Fatalf("verify: %d %s", code, body)
	}
	_, body = c.do("GET", "/api/v1/me", nil)
	var m Me
	_ = json.Unmarshal(body, &m)
	if !m.EmailVerified {
		t.Error("not verified after verify-email")
	}

	// Logout ends the session.
	if code, _ := c.do("POST", "/api/v1/auth/logout", nil); code != http.StatusNoContent {
		t.Fatalf("logout: %d", code)
	}
	if code, _ := c.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("me after logout: %d", code)
	}

	// Login by username and by e-mail (case-insensitive).
	for _, login := range []string{"anna", "Anna@Example.CH"} {
		code, body := c.do("POST", "/api/v1/auth/login", map[string]any{"login": login, "password": "sehr-geheim-123"})
		if code != http.StatusOK {
			t.Errorf("login %q: %d %s", login, code, body)
		}
	}
	if code, _ := c.do("POST", "/api/v1/auth/login", map[string]any{"login": "anna", "password": "wrong-password"}); code != http.StatusUnauthorized {
		t.Errorf("wrong password: %d", code)
	}
}

func TestDeleteAccount(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("gone@example.ch", "gone"))
	c.do("POST", "/api/v1/routes", newRouteBody("Mine", "private"))

	if code, _ := c.do("DELETE", "/api/v1/me", map[string]any{"password": "wrong-password"}); code != http.StatusForbidden {
		t.Errorf("wrong password: %d", code)
	}
	if code, body := c.do("DELETE", "/api/v1/me", map[string]any{"password": "sehr-geheim-123"}); code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", code, body)
	}
	if code, _ := c.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("me after delete: %d", code)
	}
	var n int
	_ = s.db.QueryRow(context.Background(), `SELECT (SELECT count(*) FROM users) + (SELECT count(*) FROM routes)`).Scan(&n)
	if n != 0 {
		t.Errorf("%d users/routes left", n)
	}
}

func TestSignupConflicts(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	if code, _ := c.do("POST", "/api/v1/auth/signup", signupBody("beat@example.ch", "beat")); code != http.StatusCreated {
		t.Fatal("first signup failed")
	}
	if code, body := c.do("POST", "/api/v1/auth/signup", signupBody("BEAT@example.ch", "beat2")); code != http.StatusConflict {
		t.Errorf("duplicate email: %d %s", code, body)
	}
	if code, body := c.do("POST", "/api/v1/auth/signup", signupBody("other@example.ch", "beat")); code != http.StatusConflict {
		t.Errorf("duplicate username: %d %s", code, body)
	}
	if code, _ := c.do("POST", "/api/v1/auth/signup", signupBody("bad", "x")); code != http.StatusUnprocessableEntity {
		t.Errorf("invalid input: %d", code)
	}
	noLocale := signupBody("d@example.ch", "dario")
	delete(noLocale, "locale")
	if code, body := c.do("POST", "/api/v1/auth/signup", noLocale); code != http.StatusCreated {
		t.Errorf("locale should default to de: %d %s", code, body)
	}
	bot := signupBody("bot@example.ch", "robot")
	bot["website"] = "http://spam"
	if code, _ := c.do("POST", "/api/v1/auth/signup", bot); code != http.StatusBadRequest {
		t.Errorf("honeypot: %d", code)
	}
}

func TestCrossSiteRequestsRejected(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	if code, _ := c.do("POST", "/api/v1/auth/signup", signupBody("c@example.ch", "chris"), "Origin", "https://evil.example"); code != http.StatusForbidden {
		t.Errorf("foreign origin: %d", code)
	}
	if code, _ := c.do("POST", "/api/v1/auth/logout", nil, "Sec-Fetch-Site", "cross-site"); code != http.StatusForbidden {
		t.Errorf("cross-site fetch: %d", code)
	}
	// GET stays allowed from anywhere.
	if code, _ := c.do("GET", "/api/v1/version", nil, "Origin", "https://evil.example"); code != http.StatusOK {
		t.Errorf("cross-origin GET: %d", code)
	}
}

func TestLoginRateLimit(t *testing.T) {
	lim := DefaultLimits()
	lim.LoginAccount = ratelimit.New(time.Hour, 3)
	s := newTestServer(t, lim)
	c := s.client(t)
	var last int
	for range 5 {
		last, _ = c.do("POST", "/api/v1/auth/login", map[string]any{"login": "dora", "password": "whatever"})
	}
	if last != http.StatusTooManyRequests {
		t.Errorf("5th attempt: %d, want 429", last)
	}
	// Someone else guessing dora's password does not lock dora out.
	ctx := context.WithValue(context.Background(), ipKey, "198.51.100.9")
	if !lim.LoginAccount.Allow("dora " + limitKey(ctx)) {
		t.Error("dora locked out from her own address")
	}
}

func TestPasswordResetFlow(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	c.do("POST", "/api/v1/auth/signup", signupBody("eva@example.ch", "eva"))

	if code, _ := c.do("POST", "/api/v1/auth/password/forgot", map[string]any{"email": "nobody@example.ch"}); code != http.StatusNoContent {
		t.Errorf("forgot unknown: %d", code)
	}
	if code, _ := c.do("POST", "/api/v1/auth/password/forgot", map[string]any{"email": "eva@example.ch"}); code != http.StatusNoContent {
		t.Errorf("forgot: %d", code)
	}
	msgs := s.mail.Sent()
	if len(msgs) != 2 { // verification + reset
		t.Fatalf("%d mails, want 2", len(msgs))
	}
	token := mailToken.FindStringSubmatch(msgs[1].Text)[1]
	if code, body := c.do("POST", "/api/v1/auth/password/reset", map[string]any{"token": token, "password": "neues-passwort-456"}); code != http.StatusNoContent {
		t.Fatalf("reset: %d %s", code, body)
	}
	if code, _ := c.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("session should end after reset: %d", code)
	}
	if code, _ := c.do("POST", "/api/v1/auth/login", map[string]any{"login": "eva", "password": "neues-passwort-456"}); code != http.StatusOK {
		t.Errorf("login with new password: %d", code)
	}
	if code, _ := c.do("POST", "/api/v1/auth/password/reset", map[string]any{"token": token, "password": "noch-ein-passwort"}); code != http.StatusBadRequest {
		t.Errorf("the same token again: %d, want 400", code)
	}

	// Guessing tokens is limited.
	last := 0
	for range 25 {
		last, _ = c.do("POST", "/api/v1/auth/password/reset", map[string]any{"token": "geraten-geraten-geraten", "password": "egal-egal-egal"})
	}
	if last != http.StatusTooManyRequests {
		t.Errorf("25th guess: %d, want 429", last)
	}
}
