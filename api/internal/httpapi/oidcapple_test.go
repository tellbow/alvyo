package httpapi

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/auth"
)

func TestAppleSignIn(t *testing.T) {
	idp := newFakeIDP(t)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	idp.apple = &key.PublicKey
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	const web, app = "ch.example.web", "ch.example.app"
	s := newTestServerWith(t, func(d *Deps) {
		d.OIDC = &auth.OIDC{
			Providers: []auth.OIDCProvider{{ID: "apple", Name: "Apple", Issuer: idp.URL, ClientID: web,
				TeamID: "TEAM1", KeyID: "KEY1", Key: string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
				AppID: app}},
			CallbackURL: func(id string) string { return origin + "/api/v1/auth/oidc/" + id + "/callback" },
		}
		d.Auth.Revoke = d.OIDC.Revoke
	})
	ctx := context.Background()
	revoked := func() []string {
		idp.mu.Lock()
		defer idp.mu.Unlock()
		return slices.Clone(idp.revoked)
	}

	// The website: no PKCE, the name asked for, the answer posted back from
	// Apple's site with the name beside the code.
	c := s.browser(t)
	authURL := c.location("/api/v1/auth/oidc/apple/start?redirect=/routes")
	u, _ := url.Parse(authURL)
	q := u.Query()
	if q.Get("code_challenge") != "" || q.Get("response_mode") != "form_post" || q.Get("scope") != "openid email name" {
		t.Fatalf("authorization request: %s", authURL)
	}
	code := "code-web-1"
	idp.mu.Lock()
	idp.codes[code] = idpGrant{claims: map[string]any{"iss": idp.URL, "aud": web, "sub": "a-1",
		"email": "x1@privaterelay.appleid.com", "email_verified": "true", "nonce": q.Get("nonce"),
		"iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix()}}
	idp.mu.Unlock()
	form := url.Values{"code": {code}, "state": {q.Get("state")},
		"user": {`{"name":{"firstName":"Anna","lastName":"Muster"},"email":"x1@privaterelay.appleid.com"}`}}
	req, _ := http.NewRequest("POST", s.URL+"/api/v1/auth/oidc/apple/callback", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "https://appleid.apple.com")
	req.Header.Set("Sec-Fetch-Site", "cross-site")
	resp, err := c.http.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusFound || resp.Header.Get("Location") != origin+"/routes" {
		t.Fatalf("posted callback: %d %s", resp.StatusCode, resp.Header.Get("Location"))
	}
	var m Me
	_, body := c.do("GET", "/api/v1/me", nil)
	_ = json.Unmarshal(body, &m)
	if m.DisplayName != "Anna Muster" || !m.EmailVerified || m.Username != "anna_muster" {
		t.Fatalf("account from Apple: %+v", m)
	}
	// Other posts from elsewhere are still refused.
	if code, _ := c.do("POST", "/api/v1/auth/logout", nil, "Origin", "https://appleid.apple.com"); code != http.StatusForbidden {
		t.Errorf("cross-site logout: %d", code)
	}

	// Deleting the account revokes Apple's token, issued to the website.
	if code, body := c.do("DELETE", "/api/v1/me", map[string]any{}); code != http.StatusNoContent {
		t.Fatalf("delete: %d %s", code, body)
	}
	if got := revoked(); !slices.Equal(got, []string{"rt-code-web-1"}) {
		t.Errorf("revoked after deleting: %v", got)
	}

	// The app: its identity token (for the app, with the nonce's hash) and
	// its code, redeemed as the app.
	native := func(sub, nonce, tokenNonce string) (int, []byte, *client) {
		sum := sha256.Sum256([]byte(tokenNonce))
		claims := map[string]any{"iss": idp.URL, "aud": app, "sub": sub, "email": sub + "@example.ch",
			"email_verified": true, "nonce": hex.EncodeToString(sum[:]),
			"iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix()}
		code := "code-app-" + sub
		idp.mu.Lock()
		idp.codes[code] = idpGrant{claims: claims}
		idp.mu.Unlock()
		phone := s.client(t)
		status, body := phone.do("POST", "/api/v1/auth/oidc/apple/native", map[string]any{
			"identity_token": idp.sign(claims), "authorization_code": code, "nonce": nonce, "name": "Beat Bühler"})
		return status, body, phone
	}
	if status, body, _ := native("a-2", "roh", "anders"); status != http.StatusUnauthorized {
		t.Errorf("wrong nonce: %d %s", status, body)
	}
	status, body, phone := native("a-3", "roh", "roh")
	if status != http.StatusOK || !strings.Contains(string(body), `"display_name":"Beat Bühler"`) ||
		!strings.Contains(string(body), `"username":"beat_b_hler"`) {
		t.Fatalf("native sign-in: %d %s", status, body)
	}
	var client string
	if err := s.db.QueryRow(ctx, `SELECT token_client FROM identities WHERE subject = 'a-3'`).Scan(&client); err != nil || client != app {
		t.Errorf("token for %q (%v), want the app's", client, err)
	}
	if code, _ := phone.do("GET", "/api/v1/me", nil); code != http.StatusOK {
		t.Errorf("logged in by the session cookie: %d", code)
	}

	// Apple says the person stopped using Sign in with Apple with us: the
	// identity goes. A forged notification changes nothing.
	notify := func(payload string) int {
		b, _ := json.Marshal(map[string]string{"payload": payload})
		req, _ := http.NewRequest("POST", s.URL+"/api/v1/auth/apple/notifications", strings.NewReader(string(b)))
		req.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = io.Copy(io.Discard, resp.Body)
		_ = resp.Body.Close()
		return resp.StatusCode
	}
	event := map[string]any{"iss": idp.URL + "/", "aud": app, "iat": time.Now().Unix(), "jti": "j1",
		"events": `{"type":"consent-revoked","sub":"a-3","event_time":1}`}
	forged := idp.sign(event)
	forged = forged[:len(forged)-4] + "AAAA"
	if got := notify(forged); got != http.StatusBadRequest {
		t.Errorf("forged notification: %d", got)
	}
	if got := notify(idp.sign(event)); got != http.StatusOK {
		t.Errorf("notification: %d", got)
	}
	var left int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM identities WHERE subject = 'a-3'`).Scan(&left); err != nil || left != 0 {
		t.Errorf("identity after consent-revoked: %d (%v)", left, err)
	}
}
