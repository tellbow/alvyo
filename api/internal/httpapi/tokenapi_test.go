package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/ratelimit"
)

type tokenResp struct {
	ID         string     `json:"id"`
	Name       string     `json:"name"`
	Token      string     `json:"token"`
	LastUsedAt *time.Time `json:"last_used_at"`
}

// newAccessToken creates an access token for the logged-in c.
func newAccessToken(c *client, name string) tokenResp {
	c.t.Helper()
	code, body := c.do("POST", "/api/v1/me/tokens", map[string]any{"name": name})
	var tok tokenResp
	if err := json.Unmarshal(body, &tok); code != http.StatusCreated || err != nil {
		c.t.Fatalf("create token: %d %s", code, body)
	}
	return tok
}

// bearer does a request with the token only, without the cookie.
func (s *testServer) bearer(t *testing.T, token, method, path string, body any) (int, []byte) {
	t.Helper()
	return s.client(t).do(method, path, body, "Authorization", "Bearer "+token)
}

func TestAccessTokens(t *testing.T) {
	s := newTestServer(t, Limits{})
	c, other := s.client(t), s.client(t)
	s.signup(c, "tina@example.ch", "tina")
	s.signup(other, "otto@example.ch", "otto")

	if code, _ := s.client(t).do("POST", "/api/v1/me/tokens", map[string]any{"name": "x"}); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	tok := newAccessToken(c, " Claude Desktop ")
	if !strings.HasPrefix(tok.Token, "alvyo_pat_") || tok.Name != "Claude Desktop" {
		t.Fatalf("token: %+v", tok)
	}
	var stored []byte
	if err := s.db.QueryRow(context.Background(), `SELECT token_hash FROM access_tokens WHERE id = $1`, tok.ID).Scan(&stored); err != nil || strings.Contains(string(stored), tok.Token) {
		t.Errorf("stored: %v", err)
	}

	// It reads what the account may see, and notes when it was used.
	code, body := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil)
	if code != http.StatusOK || !strings.Contains(string(body), `"username":"tina"`) {
		t.Fatalf("me with token: %d %s", code, body)
	}
	_, body = c.do("GET", "/api/v1/me/tokens", nil)
	var list struct{ Tokens []tokenResp }
	if err := json.Unmarshal(body, &list); err != nil || len(list.Tokens) != 1 || list.Tokens[0].Token != "" || list.Tokens[0].LastUsedAt == nil {
		t.Fatalf("list: %s", body)
	}

	// It changes nothing, not even its own kind.
	for _, req := range []struct{ method, path string }{
		{"POST", "/api/v1/routes"}, {"PATCH", "/api/v1/me"}, {"DELETE", "/api/v1/me"},
		{"POST", "/api/v1/me/tokens"}, {"DELETE", "/api/v1/me/tokens/" + tok.ID}, {"POST", "/api/v1/routing/leg"},
	} {
		if code, _ := s.bearer(t, tok.Token, req.method, req.path, map[string]any{}); code != http.StatusForbidden {
			t.Errorf("%s %s with token: %d, want 403", req.method, req.path, code)
		}
	}

	// A wrong token is refused, not taken as no login.
	if code, _ := s.bearer(t, "alvyo_pat_falsch", "GET", "/api/v1/discover?bbox=7,46,8,47", nil); code != http.StatusUnauthorized {
		t.Errorf("wrong token: %d", code)
	}

	// Revoked by its owner only; then it stops working.
	if code, _ := other.do("DELETE", "/api/v1/me/tokens/"+tok.ID, nil); code != http.StatusNotFound {
		t.Errorf("revoke someone else's: %d", code)
	}
	if code, _ := c.do("DELETE", "/api/v1/me/tokens/"+tok.ID, nil); code != http.StatusNoContent {
		t.Errorf("revoke: %d", code)
	}
	if code, _ := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("revoked token: %d", code)
	}

	// A banned account's tokens stop working.
	tok = newAccessToken(c, "Skript")
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET banned_at = now() WHERE username = 'tina'`); err != nil {
		t.Fatal(err)
	}
	if code, _ := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("banned: %d", code)
	}
}

func TestAccessTokenLimits(t *testing.T) {
	lim := DefaultLimits()
	lim.AccessToken = ratelimit.New(time.Hour, 3)
	s := newTestServer(t, lim)
	c := s.client(t)
	s.signup(c, "lima@example.ch", "lima")
	tok := newAccessToken(c, "Skript")
	for range 3 {
		if code, _ := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil); code != http.StatusOK {
			t.Fatalf("within the limit: %d", code)
		}
	}
	if code, _ := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil); code != http.StatusTooManyRequests {
		t.Errorf("over the limit: %d", code)
	}
	// The session is not counted.
	if code, _ := c.do("GET", "/api/v1/me", nil); code != http.StatusOK {
		t.Errorf("session: %d", code)
	}

	// At most 20 tokens.
	if _, err := s.db.Exec(context.Background(), `INSERT INTO access_tokens (user_id, name, token_hash)
		SELECT id, 'alt', sha256(g::text::bytea) FROM users, generate_series(1, 19) g WHERE username = 'lima'`); err != nil {
		t.Fatal(err)
	}
	if code, body := c.do("POST", "/api/v1/me/tokens", map[string]any{"name": "zu viel"}); code != http.StatusUnprocessableEntity {
		t.Errorf("21st token: %d %s", code, body)
	}
}

// A password reset takes the account over: the tokens go with the sessions.
func TestAccessTokensEndOnPasswordReset(t *testing.T) {
	s := newTestServer(t, Limits{})
	c := s.client(t)
	s.signup(c, "rita@example.ch", "rita")
	tok := newAccessToken(c, "Claude Code")
	if code, _ := c.do("POST", "/api/v1/auth/password/forgot", map[string]any{"email": "rita@example.ch"}); code != http.StatusNoContent {
		t.Fatalf("forgot: %d", code)
	}
	msgs := s.mail.Sent()
	reset := mailToken.FindStringSubmatch(msgs[len(msgs)-1].Text)[1]
	if code, body := c.do("POST", "/api/v1/auth/password/reset", map[string]any{"token": reset, "password": "neues-passwort-456"}); code != http.StatusNoContent {
		t.Fatalf("reset: %d %s", code, body)
	}
	if code, _ := s.bearer(t, tok.Token, "GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("token after reset: %d", code)
	}
}
