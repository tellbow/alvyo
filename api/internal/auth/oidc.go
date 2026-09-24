package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/google/uuid"
	"golang.org/x/oauth2"
)

// OIDC errors.
var (
	ErrUnknownProvider = errors.New("auth: unknown sign-in provider")
	ErrOIDCState       = errors.New("auth: sign-in expired or was started elsewhere")
	ErrOIDC            = errors.New("auth: the provider's answer was not accepted")
	ErrOIDCBusy        = errors.New("auth: too many sign-ins under way")
)

// oidcStateTTL bounds the time a person may spend at the provider.
const oidcStateTTL = 10 * time.Minute

// maxOIDCStates bounds the sign-ins under way (kept in memory).
const maxOIDCStates = 10000

// OIDCProvider is an OpenID Connect provider from the configuration.
type OIDCProvider struct {
	ID           string // in URLs and the identities table, e.g. "google"
	Name         string // on the button, e.g. "Google"
	Issuer       string
	ClientID     string
	ClientSecret string
}

// Identity is what a provider tells us about the person who signed in.
type Identity struct {
	Provider      string
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	Username      string // preferred_username, if any
}

// OIDC runs the authorization code flow (with PKCE and nonce) against the
// configured providers.
type OIDC struct {
	Providers []OIDCProvider
	// CallbackURL is where a provider sends the browser back to.
	CallbackURL func(provider string) string

	mu      sync.Mutex
	clients map[string]*oidcClient
	states  map[string]oidcState
}

type oidcClient struct {
	config   oauth2.Config
	verifier *oidc.IDTokenVerifier
}

// oidcState is a sign-in in progress.
type oidcState struct {
	provider, verifier, nonce string
	redirect                  string    // local path to return to
	link                      uuid.UUID // account to connect the identity to; uuid.Nil to log in
	until                     time.Time
}

func (o *OIDC) provider(id string) (OIDCProvider, bool) {
	for _, p := range o.Providers {
		if p.ID == id {
			return p, true
		}
	}
	return OIDCProvider{}, false
}

// client discovers a provider on first use and remembers it.
func (o *OIDC) client(ctx context.Context, id string) (*oidcClient, error) {
	p, ok := o.provider(id)
	if !ok {
		return nil, ErrUnknownProvider
	}
	o.mu.Lock()
	c := o.clients[id]
	o.mu.Unlock()
	if c != nil {
		return c, nil
	}
	// Discovery outlives the request that triggered it.
	prov, err := oidc.NewProvider(context.WithoutCancel(ctx), p.Issuer)
	if err != nil {
		return nil, fmt.Errorf("auth: discover %s: %w", id, err)
	}
	c = &oidcClient{
		config: oauth2.Config{
			ClientID: p.ClientID, ClientSecret: p.ClientSecret, Endpoint: prov.Endpoint(),
			RedirectURL: o.CallbackURL(id), Scopes: []string{oidc.ScopeOpenID, "email", "profile"},
		},
		verifier: prov.Verifier(&oidc.Config{ClientID: p.ClientID}),
	}
	o.mu.Lock()
	if o.clients == nil {
		o.clients = map[string]*oidcClient{}
	}
	o.clients[id] = c
	o.mu.Unlock()
	return c, nil
}

func random() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// Start begins a sign-in at the provider. It returns where to send the
// browser and the state to keep in a cookie until the callback.
func (o *OIDC) Start(ctx context.Context, provider, redirect string, link uuid.UUID) (authURL, state string, err error) {
	c, err := o.client(ctx, provider)
	if err != nil {
		return "", "", err
	}
	st := oidcState{provider: provider, verifier: oauth2.GenerateVerifier(), nonce: random(),
		redirect: redirect, link: link, until: time.Now().Add(oidcStateTTL)}
	state = random()
	o.mu.Lock()
	if o.states == nil {
		o.states = map[string]oidcState{}
	}
	for k, v := range o.states {
		if time.Now().After(v.until) {
			delete(o.states, k)
		}
	}
	if len(o.states) >= maxOIDCStates { // a flood of starts, never finished
		o.mu.Unlock()
		return "", "", ErrOIDCBusy
	}
	o.states[state] = st
	o.mu.Unlock()
	return c.config.AuthCodeURL(state, oidc.Nonce(st.nonce), oauth2.S256ChallengeOption(st.verifier)), state, nil
}

// Finish completes a sign-in: state must match the cookie set by Start.
// It returns the identity, where to go next and the account to link.
func (o *OIDC) Finish(ctx context.Context, provider, state, cookie, code string) (Identity, string, uuid.UUID, error) {
	o.mu.Lock()
	st, ok := o.states[state]
	delete(o.states, state)
	o.mu.Unlock()
	if !ok || state == "" || state != cookie || st.provider != provider || time.Now().After(st.until) {
		return Identity{}, "", uuid.Nil, ErrOIDCState
	}
	c, err := o.client(ctx, provider)
	if err != nil {
		return Identity{}, "", uuid.Nil, err
	}
	tok, err := c.config.Exchange(ctx, code, oauth2.VerifierOption(st.verifier))
	if err != nil {
		return Identity{}, "", uuid.Nil, fmt.Errorf("%w: %w", ErrOIDC, err)
	}
	raw, ok := tok.Extra("id_token").(string)
	if !ok {
		return Identity{}, "", uuid.Nil, fmt.Errorf("%w: no id_token", ErrOIDC)
	}
	idt, err := c.verifier.Verify(ctx, raw)
	if err != nil {
		return Identity{}, "", uuid.Nil, fmt.Errorf("%w: %w", ErrOIDC, err)
	}
	if idt.Nonce != st.nonce {
		return Identity{}, "", uuid.Nil, fmt.Errorf("%w: nonce", ErrOIDC)
	}
	var claims struct {
		Email             string `json:"email"`
		EmailVerified     any    `json:"email_verified"` // bool, or "true" at some providers
		Name              string `json:"name"`
		PreferredUsername string `json:"preferred_username"`
	}
	if err := idt.Claims(&claims); err != nil {
		return Identity{}, "", uuid.Nil, fmt.Errorf("%w: %w", ErrOIDC, err)
	}
	verified := claims.EmailVerified == true || claims.EmailVerified == "true"
	return Identity{
		Provider: provider, Subject: idt.Subject, Email: strings.TrimSpace(claims.Email), EmailVerified: verified,
		Name: strings.TrimSpace(claims.Name), Username: claims.PreferredUsername,
	}, st.redirect, st.link, nil
}
