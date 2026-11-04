package httpapi

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"

	"github.com/tellbow/alvyo/api/internal/auth"
)

// fakeIDP is a minimal OpenID Connect provider: discovery, keys and a token
// endpoint that checks PKCE, or, for codes without a challenge, Apple's
// signed client secret. Tests authorize codes directly.
type fakeIDP struct {
	*httptest.Server
	key   *rsa.PrivateKey
	mu    sync.Mutex
	codes map[string]idpGrant
	// apple checks client secrets (Sign in with Apple); revoked collects
	// the refresh tokens revoked with them.
	apple   *ecdsa.PublicKey
	revoked []string
}

type idpGrant struct {
	challenge string
	claims    map[string]any
}

func newFakeIDP(t *testing.T) *fakeIDP {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	idp := &fakeIDP{key: key, codes: map[string]idpGrant{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/openid-configuration", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"issuer": idp.URL, "authorization_endpoint": idp.URL + "/authorize", "token_endpoint": idp.URL + "/token",
			"jwks_uri": idp.URL + "/jwks", "id_token_signing_alg_values_supported": []string{"RS256"},
			"revocation_endpoint": idp.URL + "/revoke",
		})
	})
	mux.HandleFunc("GET /jwks", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{
			{Key: &key.PublicKey, KeyID: "k1", Algorithm: "RS256", Use: "sig"}}})
	})
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		idp.mu.Lock()
		g, ok := idp.codes[r.Form.Get("code")]
		delete(idp.codes, r.Form.Get("code"))
		idp.mu.Unlock()
		sum := sha256.Sum256([]byte(r.Form.Get("code_verifier")))
		if !ok || (g.challenge != "" && base64.RawURLEncoding.EncodeToString(sum[:]) != g.challenge) ||
			(g.challenge == "" && !idp.appleSecret(r.Form)) {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"invalid_grant"}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "token_type": "Bearer",
			"id_token": idp.sign(g.claims), "refresh_token": "rt-" + r.Form.Get("code")})
	})
	mux.HandleFunc("POST /revoke", func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		if !idp.appleSecret(r.Form) || r.Form.Get("token_type_hint") != "refresh_token" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		idp.mu.Lock()
		idp.revoked = append(idp.revoked, r.Form.Get("token"))
		idp.mu.Unlock()
	})
	idp.Server = httptest.NewServer(mux)
	t.Cleanup(idp.Close)
	return idp
}

// sign signs claims with the provider's key.
func (idp *fakeIDP) sign(claims map[string]any) string {
	signer, _ := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: idp.key},
		(&jose.SignerOptions{}).WithType("JWT").WithHeader("kid", "k1"))
	payload, _ := json.Marshal(claims)
	jws, _ := signer.Sign(payload)
	token, _ := jws.CompactSerialize()
	return token
}

// appleSecret checks a client secret as Apple does: signed with the
// developer's key, by the team, for the client id in the form.
func (idp *fakeIDP) appleSecret(f url.Values) bool {
	if idp.apple == nil {
		return false
	}
	jws, err := jose.ParseSigned(f.Get("client_secret"), []jose.SignatureAlgorithm{jose.ES256})
	if err != nil || jws.Signatures[0].Header.KeyID != "KEY1" {
		return false
	}
	payload, err := jws.Verify(idp.apple)
	if err != nil {
		return false
	}
	var c struct {
		Iss, Sub, Aud string
		Exp           int64
	}
	return json.Unmarshal(payload, &c) == nil && c.Iss == "TEAM1" && c.Sub == f.Get("client_id") &&
		c.Aud == idp.URL && c.Exp > time.Now().Unix()
}

// authorize plays the provider's login page: it answers the authorization
// request at authURL for the person with claims, returning the code.
func (idp *fakeIDP) authorize(t *testing.T, authURL string, claims map[string]any) (code, state string) {
	t.Helper()
	u, err := url.Parse(authURL)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if q.Get("code_challenge_method") != "S256" {
		t.Fatalf("no PKCE in %s", authURL)
	}
	c := map[string]any{"iss": idp.URL, "aud": "alvyo", "exp": time.Now().Add(time.Hour).Unix(),
		"iat": time.Now().Unix(), "nonce": q.Get("nonce")}
	for k, v := range claims {
		c[k] = v
	}
	code = "code-" + q.Get("state")[:8]
	idp.mu.Lock()
	idp.codes[code] = idpGrant{challenge: q.Get("code_challenge"), claims: c}
	idp.mu.Unlock()
	return code, q.Get("state")
}

// browser is a client that does not follow redirects, like a test of each
// hop, keeping cookies.
func (s *testServer) browser(t *testing.T) *client {
	jar, _ := cookiejar.New(nil)
	return &client{t: t, base: s.URL, http: &http.Client{Jar: jar,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}

// location GETs path and returns the redirect target.
func (c *client) location(path string) string {
	c.t.Helper()
	req, _ := http.NewRequest("GET", c.base+path, nil)
	resp, err := c.http.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusFound {
		c.t.Fatalf("GET %s: %d, want 302", path, resp.StatusCode)
	}
	return resp.Header.Get("Location")
}

func TestOIDCFromTheApp(t *testing.T) {
	idp := newFakeIDP(t)
	s := newTestServerWith(t, func(d *Deps) {
		d.OIDC = &auth.OIDC{
			Providers:   []auth.OIDCProvider{{ID: "test", Name: "Test-ID", Issuer: idp.URL, ClientID: "alvyo", ClientSecret: "geheim"}},
			CallbackURL: func(id string) string { return origin + "/api/v1/auth/oidc/" + id + "/callback" },
		}
	})
	const verifier = "the-apps-verifier-that-nobody-else-knows-012"
	sum := sha256.Sum256([]byte(verifier))
	start := "/api/v1/auth/oidc/test/start?app_locale=it&app_challenge=" + base64.RawURLEncoding.EncodeToString(sum[:])
	signIn := func(c *client, claims map[string]any) string {
		t.Helper()
		code, state := idp.authorize(t, c.location(start), claims)
		return c.location("/api/v1/auth/oidc/test/callback?code=" + code + "&state=" + state)
	}
	codeOf := func(to string) string {
		t.Helper()
		code, ok := strings.CutPrefix(to, "alvyo://signin?code=")
		if !ok {
			t.Fatalf("not back to the app with a code: %s", to)
		}
		return code
	}

	// The browser goes back into the app, and is not logged in itself.
	browser := s.browser(t)
	to := signIn(browser, map[string]any{"sub": "a-1", "email": "app@example.ch", "email_verified": true})
	if code, _ := browser.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("browser after the app's sign-in: %d, want 401", code)
	}

	// Whoever catches the link without the verifier gets nothing, and the
	// code is gone.
	app := s.client(t)
	body := map[string]any{"code": codeOf(to), "verifier": "someone-else"}
	if code, _ := app.do("POST", "/api/v1/auth/app-sign-in", body); code != http.StatusUnauthorized {
		t.Errorf("wrong verifier: %d, want 401", code)
	}
	body["verifier"] = verifier
	if code, _ := app.do("POST", "/api/v1/auth/app-sign-in", body); code != http.StatusUnauthorized {
		t.Errorf("code used twice: %d, want 401", code)
	}

	// With the verifier the app logs in, in its language.
	to = signIn(browser, map[string]any{"sub": "a-1"})
	code, answer := app.do("POST", "/api/v1/auth/app-sign-in", map[string]any{"code": codeOf(to), "verifier": verifier})
	if code != http.StatusOK || !strings.Contains(string(answer), `"username":"app"`) {
		t.Fatalf("app sign-in: %d %s", code, answer)
	}
	if code, body := app.do("GET", "/api/v1/me", nil); code != http.StatusOK || !strings.Contains(string(body), `"locale":"it"`) {
		t.Errorf("session in the app: %d %s", code, body)
	}

	// Refusals reach the app too.
	owner := s.client(t)
	s.signup(owner, "alt@example.ch", "alt")
	if to := signIn(browser, map[string]any{"sub": "a-2", "email": "alt@example.ch", "email_verified": true}); to != "alvyo://signin?oidc=exists" {
		t.Errorf("existing e-mail: %s", to)
	}
	browser.location(start)
	if to := browser.location("/api/v1/auth/oidc/test/callback?error=access_denied"); to != "alvyo://signin?oidc=cancelled" {
		t.Errorf("cancelled: %s", to)
	}

	// A later sign-in on the website in the same browser stays the website's.
	browser.location(start)
	code2, state := idp.authorize(t, browser.location("/api/v1/auth/oidc/test/start"), map[string]any{"sub": "a-1"})
	if to := browser.location("/api/v1/auth/oidc/test/callback?code=" + code2 + "&state=" + state); to != origin+"/" {
		t.Errorf("website after an unfinished app sign-in: %s", to)
	}
}

func TestOIDC(t *testing.T) {
	idp := newFakeIDP(t)
	s := newTestServerWith(t, func(d *Deps) {
		d.OIDC = &auth.OIDC{
			Providers:   []auth.OIDCProvider{{ID: "test", Name: "Test-ID", Issuer: idp.URL, ClientID: "alvyo", ClientSecret: "geheim"}},
			CallbackURL: func(id string) string { return origin + "/api/v1/auth/oidc/" + id + "/callback" },
		}
	})
	// signIn runs the whole flow for claims and returns where the browser ends up.
	signIn := func(c *client, start string, claims map[string]any) string {
		t.Helper()
		code, state := idp.authorize(t, c.location(start), claims)
		return c.location("/api/v1/auth/oidc/test/callback?code=" + code + "&state=" + state)
	}
	me := func(c *client) Me {
		var m Me
		code, body := c.do("GET", "/api/v1/me", nil)
		if code != http.StatusOK {
			return m
		}
		_ = json.Unmarshal(body, &m)
		return m
	}

	if _, body := s.client(t).do("GET", "/api/v1/auth/providers", nil); !strings.Contains(string(body), `{"id":"test","name":"Test-ID"}`) {
		t.Errorf("providers: %s", body)
	}

	// A new person gets an account without password, verified by the provider.
	newcomer := map[string]any{"sub": "u-1", "email": "neu@example.ch", "email_verified": true, "name": "Neu Nutzer"}
	c := s.browser(t)
	if to := signIn(c, "/api/v1/auth/oidc/test/start?redirect=/routes", newcomer); to != origin+"/routes" {
		t.Fatalf("after sign-up: %s", to)
	}
	if m := me(c); m.Username != "neu" || !m.EmailVerified || m.HasPassword || m.DisplayName != "Neu Nutzer" {
		t.Fatalf("new account: %+v", m)
	}
	// Again: the same account.
	again := s.browser(t)
	signIn(again, "/api/v1/auth/oidc/test/start?redirect=//evil.example", newcomer)
	if m := me(again); m.Username != "neu" {
		t.Errorf("second sign-in: %+v", m)
	}

	// An existing e-mail address is not taken over.
	owner := s.browser(t)
	s.signup(owner, "alt@example.ch", "alt")
	existing := map[string]any{"sub": "u-2", "email": "alt@example.ch", "email_verified": true}
	stranger := s.browser(t)
	if to := signIn(stranger, "/api/v1/auth/oidc/test/start", existing); to != origin+"/login?oidc=exists" {
		t.Errorf("existing e-mail: %s", to)
	}
	if me(stranger).Username != "" {
		t.Error("logged in to an existing account by e-mail")
	}
	// Only a verified address's owner, just logged in, connects a provider:
	// it would outlast a password reset by the address's real owner.
	ctx := context.Background()
	if to := owner.location("/api/v1/auth/oidc/test/start?link=true"); to != origin+"/account?oidc=verify" {
		t.Errorf("link before the address is confirmed: %s", to)
	}
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE username = 'alt'`); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(ctx, `UPDATE sessions SET created_at = now() - interval '1 hour'`); err != nil {
		t.Fatal(err)
	}
	if to := owner.location("/api/v1/auth/oidc/test/start?link=true"); to != origin+"/account?oidc=again" {
		t.Errorf("link from an old session: %s", to)
	}
	if _, err := s.db.Exec(ctx, `UPDATE sessions SET created_at = now()`); err != nil {
		t.Fatal(err)
	}
	// Its owner connects the provider; then the provider logs in.
	if to := signIn(owner, "/api/v1/auth/oidc/test/start?link=true", existing); to != origin+"/account?oidc=linked" {
		t.Fatalf("link: %s", to)
	}
	if signIn(stranger, "/api/v1/auth/oidc/test/start", existing); me(stranger).Username != "alt" {
		t.Error("connected provider does not log in")
	}
	if to := signIn(owner, "/api/v1/auth/oidc/test/start?link=true", newcomer); to != origin+"/account?oidc=taken" {
		t.Errorf("someone else's identity: %s", to)
	}
	if to := signIn(owner, "/api/v1/auth/oidc/test/start?link=true", map[string]any{"sub": "u-9"}); to != origin+"/account?oidc=already" {
		t.Errorf("second identity at the same provider: %s", to)
	}
	_, body := owner.do("GET", "/api/v1/me/identities", nil)
	if !strings.Contains(string(body), `"provider":"test","email":"alt@example.ch"`) {
		t.Errorf("identities: %s", body)
	}

	// The callback only works in the browser that started it.
	other := s.browser(t)
	code, state := idp.authorize(t, other.location("/api/v1/auth/oidc/test/start"), newcomer)
	if to := s.browser(t).location("/api/v1/auth/oidc/test/callback?code=" + code + "&state=" + state); to != origin+"/login?oidc=failed" {
		t.Errorf("callback in another browser: %s", to)
	}

	// Taken usernames get a number; unverified addresses get a mail.
	sent := len(s.mail.Sent())
	cousin := s.browser(t)
	signIn(cousin, "/api/v1/auth/oidc/test/start", map[string]any{"sub": "u-3", "email": "neu@example.org", "email_verified": "false"})
	if m := me(cousin); m.Username != "neu2" || m.EmailVerified {
		t.Errorf("second 'neu': %+v", m)
	}
	if len(s.mail.Sent()) != sent+1 {
		t.Error("no verification mail for an unverified address")
	}

	// The only way to log in cannot be disconnected; a fresh login confirms
	// deleting an account without password.
	if code, _ := c.do("DELETE", "/api/v1/me/identities/test", nil); code != http.StatusConflict {
		t.Errorf("unlink the last login: %d, want 409", code)
	}
	if code, body := c.do("DELETE", "/api/v1/me", map[string]any{}); code != http.StatusNoContent {
		t.Errorf("delete a passwordless account: %d %s", code, body)
	}
}
