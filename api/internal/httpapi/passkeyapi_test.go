package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/descope/virtualwebauthn"
	"github.com/google/uuid"
)

func TestPasskeys(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	rp := virtualwebauthn.RelyingParty{ID: "alvyo.test", Name: "alvyo", Origin: origin}
	c := s.client(t)
	s.signup(c, "hiker@example.ch", "hiker")
	var id uuid.UUID
	if err := s.db.QueryRow(ctx, `SELECT id FROM users WHERE username = 'hiker'`).Scan(&id); err != nil {
		t.Fatal(err)
	}

	// Only with the address confirmed: a passkey outlasts a password reset.
	code, body := c.do("POST", "/api/v1/me/passkeys/begin", map[string]any{"password": "sehr-geheim-123"})
	if code != http.StatusForbidden || !strings.Contains(string(body), "confirm your e-mail") {
		t.Errorf("begin before confirming the address: %d %s", code, body)
	}
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now()`); err != nil {
		t.Fatal(err)
	}

	// Adding a passkey needs the password again.
	if code, _ := c.do("POST", "/api/v1/me/passkeys/begin", map[string]any{"password": "falsch"}); code != http.StatusForbidden {
		t.Errorf("begin with a wrong password: %d, want 403", code)
	}
	code, body = c.do("POST", "/api/v1/me/passkeys/begin", map[string]any{"password": "sehr-geheim-123"})
	var begin struct {
		Ceremony string          `json:"ceremony"`
		Options  json.RawMessage `json:"options"`
	}
	_ = json.Unmarshal(body, &begin)
	if code != http.StatusOK || begin.Ceremony == "" {
		t.Fatalf("begin registration: %d %s", code, body)
	}
	authenticator := virtualwebauthn.NewAuthenticatorWithOptions(virtualwebauthn.AuthenticatorOptions{UserHandle: id[:]})
	cred := virtualwebauthn.NewCredential(virtualwebauthn.KeyTypeEC2)
	opts, err := virtualwebauthn.ParseAttestationOptions(string(begin.Options))
	if err != nil {
		t.Fatal(err)
	}
	attestation := virtualwebauthn.CreateAttestationResponse(rp, authenticator, cred, *opts)
	code, body = c.do("POST", "/api/v1/me/passkeys", map[string]any{
		"ceremony": begin.Ceremony, "name": "Laptop", "response": json.RawMessage(attestation)})
	if code != http.StatusOK || !strings.Contains(string(body), `"name":"Laptop"`) {
		t.Fatalf("finish registration: %d %s", code, body)
	}
	authenticator.AddCredential(cred)
	// A ceremony is answered once.
	if code, _ := c.do("POST", "/api/v1/me/passkeys", map[string]any{
		"ceremony": begin.Ceremony, "name": "Again", "response": json.RawMessage(attestation)}); code != http.StatusConflict {
		t.Errorf("reused ceremony: %d, want 409", code)
	}

	// Log in with it, without username or password.
	login := func(cl *client, a virtualwebauthn.Authenticator) (int, string) {
		_, body := cl.do("POST", "/api/v1/auth/passkey/begin", nil)
		var b struct {
			Ceremony string          `json:"ceremony"`
			Options  json.RawMessage `json:"options"`
		}
		_ = json.Unmarshal(body, &b)
		o, err := virtualwebauthn.ParseAssertionOptions(string(b.Options))
		if err != nil {
			t.Fatal(err)
		}
		// A discoverable login names no credentials: the authenticator picks.
		assertion := virtualwebauthn.CreateAssertionResponse(rp, a, a.Credentials[0], *o)
		code, resp := cl.do("POST", "/api/v1/auth/passkey", map[string]any{"ceremony": b.Ceremony, "response": json.RawMessage(assertion)})
		return code, string(resp)
	}
	fresh := s.client(t)
	if code, resp := login(fresh, authenticator); code != http.StatusOK || !strings.Contains(resp, `"username":"hiker"`) {
		t.Fatalf("passkey login: %d %s", code, resp)
	}
	if code, body := fresh.do("GET", "/api/v1/me", nil); code != http.StatusOK || !strings.Contains(string(body), "hiker") {
		t.Errorf("session after passkey login: %d", code)
	}
	_, body = c.do("GET", "/api/v1/me/passkeys", nil)
	if !strings.Contains(string(body), `"last_used_at"`) {
		t.Errorf("last use not recorded: %s", body)
	}

	// Someone else's key does not get in.
	stranger := virtualwebauthn.NewAuthenticatorWithOptions(virtualwebauthn.AuthenticatorOptions{UserHandle: id[:]})
	stranger.AddCredential(virtualwebauthn.NewCredential(virtualwebauthn.KeyTypeEC2))
	if code, _ := login(s.client(t), stranger); code != http.StatusUnprocessableEntity {
		t.Errorf("unknown passkey: %d, want 422", code)
	}

	// Removing it; the password still logs in.
	var list struct {
		Passkeys []struct {
			ID string `json:"id"`
		} `json:"passkeys"`
	}
	_ = json.Unmarshal(body, &list)
	if code, _ := c.do("DELETE", "/api/v1/me/passkeys/"+list.Passkeys[0].ID, nil); code != http.StatusOK {
		t.Errorf("delete passkey: %d", code)
	}
	if code, _ := login(s.client(t), authenticator); code != http.StatusUnprocessableEntity {
		t.Errorf("deleted passkey still logs in: %d", code)
	}
}
