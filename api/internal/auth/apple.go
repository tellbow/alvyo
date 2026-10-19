package auth

import (
	"context"
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/go-jose/go-jose/v4"
	"golang.org/x/oauth2"
)

// Sign in with Apple differs from other OpenID Connect providers: its client
// secret is a short-lived JWT signed with a key from the developer account,
// it posts its answer back (form_post), gives the name only on the first
// sign-in and outside the ID token, knows no PKCE, and apps that offer it
// must revoke its tokens when an account is deleted (App Store guideline
// 5.1.1(v)).

// appleKey signs client secrets.
type appleKey struct {
	teamID, keyID, audience string
	key                     *ecdsa.PrivateKey
}

func parseAppleKey(p OIDCProvider) (*appleKey, error) {
	block, _ := pem.Decode([]byte(p.Key))
	if block == nil {
		return nil, fmt.Errorf("auth: %s key: not PEM", p.ID)
	}
	k, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("auth: %s key: %w", p.ID, err)
	}
	ec, ok := k.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("auth: %s key: not an EC key", p.ID)
	}
	return &appleKey{teamID: p.TeamID, keyID: p.KeyID, audience: p.Issuer, key: ec}, nil
}

// secret is a client secret for clientID, valid for five minutes (Apple
// allows up to six months; a fresh one for each call needs no renewal).
func (a *appleKey) secret(clientID string) (string, error) {
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.ES256, Key: a.key},
		(&jose.SignerOptions{}).WithType("JWT").WithHeader("kid", a.keyID))
	if err != nil {
		return "", err
	}
	now := time.Now()
	payload, err := json.Marshal(map[string]any{
		"iss": a.teamID, "sub": clientID, "aud": a.audience,
		"iat": now.Unix(), "exp": now.Add(5 * time.Minute).Unix(),
	})
	if err != nil {
		return "", err
	}
	jws, err := signer.Sign(payload)
	if err != nil {
		return "", err
	}
	return jws.CompactSerialize()
}

// exchange redeems an authorization code with a fresh client secret.
func (a *appleKey) exchange(ctx context.Context, cfg oauth2.Config, code string) (*oauth2.Token, error) {
	secret, err := a.secret(cfg.ClientID)
	if err != nil {
		return nil, err
	}
	cfg.ClientSecret = secret
	return cfg.Exchange(ctx, code)
}

// appleName reads the name Apple posts as JSON on the first sign-in.
func appleName(user string) string {
	var u struct {
		Name struct {
			FirstName string `json:"firstName"`
			LastName  string `json:"lastName"`
		} `json:"name"`
	}
	if json.Unmarshal([]byte(user), &u) != nil {
		return ""
	}
	return strings.TrimSpace(u.Name.FirstName + " " + u.Name.LastName)
}

// appleClient is the configured Apple provider's client.
func (o *OIDC) appleClient(ctx context.Context, provider string) (OIDCProvider, *oidcClient, error) {
	p, ok := o.provider(provider)
	if !ok || p.Key == "" {
		return OIDCProvider{}, nil, ErrUnknownProvider
	}
	c, err := o.client(ctx, provider)
	return p, c, err
}

// AppleNative signs in with the iOS app's own Apple sign-in: idToken must be
// for the app (its bundle id) and carry the SHA-256 (hex) of rawNonce, which
// the app asked Apple for. The authorization code is redeemed for the refresh
// token that revokes the sign-in later. name is what the app got from Apple on
// the first sign-in.
func (o *OIDC) AppleNative(ctx context.Context, provider, idToken, code, rawNonce, name string) (Identity, error) {
	p, c, err := o.appleClient(ctx, provider)
	if err != nil {
		return Identity{}, err
	}
	if p.AppID == "" {
		return Identity{}, ErrUnknownProvider
	}
	sum := sha256.Sum256([]byte(rawNonce))
	want := hex.EncodeToString(sum[:])
	v := c.provider.Verifier(&oidc.Config{ClientID: p.AppID})
	id, err := identityFrom(ctx, v, (&oauth2.Token{}).WithExtra(map[string]any{"id_token": idToken}), provider,
		func(n string) bool { return rawNonce != "" && n == want })
	if err != nil {
		return Identity{}, err
	}
	tok, err := c.apple.exchange(ctx, oauth2.Config{ClientID: p.AppID, Endpoint: c.config.Endpoint}, code)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: %w", ErrOIDC, err)
	}
	// The redeemed code must be the same person's.
	redeemed, err := identityFrom(ctx, v, tok, provider, func(string) bool { return true })
	if err != nil {
		return Identity{}, err
	}
	if redeemed.Subject != id.Subject {
		return Identity{}, fmt.Errorf("%w: code of someone else", ErrOIDC)
	}
	if r := []rune(strings.TrimSpace(name)); len(r) > 0 {
		id.Name = string(r[:min(len(r), 100)])
		id.Username = id.Name // as on the website
	}
	id.RefreshToken, id.TokenClient = tok.RefreshToken, p.AppID
	return id, nil
}

// Revoke ends a sign-in at Apple with the refresh token clientID got.
// Other providers keep no tokens: nothing to do.
func (o *OIDC) Revoke(ctx context.Context, provider, clientID, token string) error {
	_, c, err := o.appleClient(ctx, provider)
	if errors.Is(err, ErrUnknownProvider) {
		return nil
	}
	if err != nil {
		return err
	}
	var meta struct {
		Revocation string `json:"revocation_endpoint"`
	}
	if err := c.provider.Claims(&meta); err != nil || meta.Revocation == "" {
		return fmt.Errorf("auth: %s has no revocation endpoint", provider)
	}
	secret, err := c.apple.secret(clientID)
	if err != nil {
		return err
	}
	form := url.Values{"client_id": {clientID}, "client_secret": {secret},
		"token": {token}, "token_type_hint": {"refresh_token"}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, meta.Revocation, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("auth: revoking at %s: %s", provider, resp.Status)
	}
	return nil
}

// AppleEvent is a server-to-server notification from Apple about a person:
// Type is email-disabled, email-enabled, consent-revoked or account-delete.
type AppleEvent struct {
	Provider, Type, Subject string
}

// AppleEvent checks a notification's payload (a JWT signed by Apple, for the
// website or the app) and reads it.
func (o *OIDC) AppleEvent(ctx context.Context, payload string) (AppleEvent, error) {
	for _, p := range o.Providers {
		if p.Key == "" {
			continue
		}
		_, c, err := o.appleClient(ctx, p.ID)
		if err != nil {
			return AppleEvent{}, err
		}
		// Notifications carry no expiry, and their issuer may end in a slash.
		idt, err := c.provider.Verifier(&oidc.Config{SkipClientIDCheck: true, SkipExpiryCheck: true,
			SkipIssuerCheck: true}).Verify(ctx, payload)
		if err != nil {
			return AppleEvent{}, fmt.Errorf("%w: %w", ErrOIDC, err)
		}
		if strings.TrimSuffix(idt.Issuer, "/") != strings.TrimSuffix(p.Issuer, "/") ||
			!slices.ContainsFunc(idt.Audience, func(a string) bool { return a == p.ClientID || (a != "" && a == p.AppID) }) {
			return AppleEvent{}, fmt.Errorf("%w: issuer or audience", ErrOIDC)
		}
		// events is JSON in a string.
		var claims struct {
			Events json.RawMessage `json:"events"`
		}
		if err := idt.Claims(&claims); err != nil {
			return AppleEvent{}, fmt.Errorf("%w: %w", ErrOIDC, err)
		}
		raw := []byte(claims.Events)
		var s string
		if json.Unmarshal(raw, &s) == nil {
			raw = []byte(s)
		}
		var ev struct {
			Type string `json:"type"`
			Sub  string `json:"sub"`
		}
		if err := json.Unmarshal(raw, &ev); err != nil || ev.Type == "" || ev.Sub == "" {
			return AppleEvent{}, fmt.Errorf("%w: events", ErrOIDC)
		}
		return AppleEvent{Provider: p.ID, Type: ev.Type, Subject: ev.Sub}, nil
	}
	return AppleEvent{}, ErrUnknownProvider
}
