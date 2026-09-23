package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"sync"
	"time"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/odysgeh/api/internal/dbq"
)

// Passkey errors.
var (
	ErrPasskey        = errors.New("auth: passkey not accepted")
	ErrCeremony       = errors.New("auth: passkey request expired; start again")
	ErrPasskeyMissing = errors.New("auth: no such passkey")
)

// MaxPasskeys per account.
const MaxPasskeys = 10

// ceremonyTTL bounds the time between asking for and answering a passkey
// prompt.
const ceremonyTTL = 5 * time.Minute

// NewWebAuthn configures passkeys for the web app at publicURL (its host is
// the relying party id).
func NewWebAuthn(publicURL string) (*webauthn.WebAuthn, error) {
	u, err := url.Parse(publicURL)
	if err != nil {
		return nil, err
	}
	return webauthn.New(&webauthn.Config{
		RPID:          u.Hostname(),
		RPDisplayName: "odysgeh",
		RPOrigins:     []string{u.Scheme + "://" + u.Host},
	})
}

// ceremonies holds pending passkey prompts in memory (one API instance).
type ceremonies struct {
	mu sync.Mutex
	m  map[string]ceremony
}

type ceremony struct {
	user    uuid.UUID // registration: whose passkey; uuid.Nil for login
	session webauthn.SessionData
	until   time.Time
}

func (c *ceremonies) put(user uuid.UUID, s *webauthn.SessionData) string {
	b := make([]byte, 18)
	_, _ = rand.Read(b)
	id := base64.RawURLEncoding.EncodeToString(b)
	now := time.Now()
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.m == nil {
		c.m = map[string]ceremony{}
	}
	for k, v := range c.m {
		if now.After(v.until) {
			delete(c.m, k)
		}
	}
	c.m[id] = ceremony{user: user, session: *s, until: now.Add(ceremonyTTL)}
	return id
}

// take returns and forgets a ceremony (each can be answered once).
func (c *ceremonies) take(id string, user uuid.UUID) (webauthn.SessionData, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	v, ok := c.m[id]
	delete(c.m, id)
	if !ok || v.user != user || time.Now().After(v.until) {
		return webauthn.SessionData{}, false
	}
	return v.session, true
}

// waUser is a user as the WebAuthn library sees them.
type waUser struct {
	u     dbq.User
	creds []webauthn.Credential
}

func (w waUser) WebAuthnID() []byte                         { return w.u.ID[:] }
func (w waUser) WebAuthnName() string                       { return w.u.Username }
func (w waUser) WebAuthnDisplayName() string                { return w.u.DisplayName }
func (w waUser) WebAuthnCredentials() []webauthn.Credential { return w.creds }

func (s *Service) credentials(ctx context.Context, user uuid.UUID) ([]webauthn.Credential, error) {
	rows, err := s.DB.Query(ctx, `SELECT credential FROM passkeys WHERE user_id = $1`, user)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (webauthn.Credential, error) {
		var c webauthn.Credential
		var raw []byte
		if err := r.Scan(&raw); err != nil {
			return c, err
		}
		return c, json.Unmarshal(raw, &c)
	})
}

// BeginPasskeyRegistration asks the browser to create a passkey for u. It
// returns the options for navigator.credentials.create and the ceremony id.
func (s *Service) BeginPasskeyRegistration(ctx context.Context, u dbq.User) (protocol.PublicKeyCredentialCreationOptions, string, error) {
	creds, err := s.credentials(ctx, u.ID)
	if err != nil {
		return protocol.PublicKeyCredentialCreationOptions{}, "", err
	}
	if len(creds) >= MaxPasskeys {
		return protocol.PublicKeyCredentialCreationOptions{}, "", fmt.Errorf("%w: at most %d passkeys", ErrPasskey, MaxPasskeys)
	}
	exclude := make([]protocol.CredentialDescriptor, len(creds))
	for i := range creds {
		exclude[i] = creds[i].Descriptor()
	}
	creation, session, err := s.WebAuthn.BeginRegistration(waUser{u, creds},
		webauthn.WithResidentKeyRequirement(protocol.ResidentKeyRequirementRequired),
		webauthn.WithExclusions(exclude))
	if err != nil {
		return protocol.PublicKeyCredentialCreationOptions{}, "", err
	}
	return creation.Response, s.passkeyCeremonies.put(u.ID, session), nil
}

// FinishPasskeyRegistration checks the browser's answer and stores the
// passkey under name.
func (s *Service) FinishPasskeyRegistration(ctx context.Context, u dbq.User, ceremonyID, name string, response []byte) error {
	session, ok := s.passkeyCeremonies.take(ceremonyID, u.ID)
	if !ok {
		return ErrCeremony
	}
	parsed, err := protocol.ParseCredentialCreationResponseBody(bytes.NewReader(response))
	if err != nil {
		return fmt.Errorf("%w: %w", ErrPasskey, err)
	}
	creds, err := s.credentials(ctx, u.ID)
	if err != nil {
		return err
	}
	cred, err := s.WebAuthn.CreateCredential(waUser{u, creds}, session, parsed)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrPasskey, err)
	}
	raw, err := json.Marshal(cred)
	if err != nil {
		return err
	}
	_, err = s.DB.Exec(ctx, `INSERT INTO passkeys (id, user_id, name, credential) VALUES ($1, $2, $3, $4)`,
		cred.ID, u.ID, name, raw)
	return err
}

// BeginPasskeyLogin asks the browser for any passkey of this site.
func (s *Service) BeginPasskeyLogin() (protocol.PublicKeyCredentialRequestOptions, string, error) {
	assertion, session, err := s.WebAuthn.BeginDiscoverableLogin(webauthn.WithUserVerification(protocol.VerificationPreferred))
	if err != nil {
		return protocol.PublicKeyCredentialRequestOptions{}, "", err
	}
	return assertion.Response, s.passkeyCeremonies.put(uuid.Nil, session), nil
}

// FinishPasskeyLogin checks the browser's answer and logs the owner of the
// passkey in.
func (s *Service) FinishPasskeyLogin(ctx context.Context, ceremonyID string, response []byte, userAgent string) (dbq.User, Session, error) {
	session, ok := s.passkeyCeremonies.take(ceremonyID, uuid.Nil)
	if !ok {
		return dbq.User{}, Session{}, ErrCeremony
	}
	parsed, err := protocol.ParseCredentialRequestResponseBody(bytes.NewReader(response))
	if err != nil {
		return dbq.User{}, Session{}, fmt.Errorf("%w: %w", ErrPasskey, err)
	}
	var owner dbq.User
	find := func(_, userHandle []byte) (webauthn.User, error) {
		id, err := uuid.FromBytes(userHandle)
		if err != nil {
			return nil, ErrPasskey
		}
		if owner, err = s.q().GetUserByID(ctx, id); err != nil {
			return nil, ErrPasskey
		}
		creds, err := s.credentials(ctx, id)
		if err != nil {
			return nil, err
		}
		return waUser{owner, creds}, nil
	}
	_, cred, err := s.WebAuthn.ValidatePasskeyLogin(find, session, parsed)
	if err != nil {
		return dbq.User{}, Session{}, fmt.Errorf("%w: %w", ErrPasskey, err)
	}
	if owner.BannedAt != nil {
		return dbq.User{}, Session{}, ErrBanned
	}
	// Keep the sign counter and flags current.
	if raw, err := json.Marshal(cred); err == nil {
		_, _ = s.DB.Exec(ctx, `UPDATE passkeys SET credential = $2, last_used_at = now() WHERE id = $1`, cred.ID, raw)
	}
	sess, err := s.createSession(ctx, owner, userAgent)
	return owner, sess, err
}

// PasskeyInfo describes a stored passkey.
type PasskeyInfo struct {
	ID       string     `json:"id" doc:"Credential id (base64url)"`
	Name     string     `json:"name"`
	Created  time.Time  `json:"created_at"`
	LastUsed *time.Time `json:"last_used_at,omitempty"`
}

// Passkeys lists the passkeys of a user.
func (s *Service) Passkeys(ctx context.Context, user uuid.UUID) ([]PasskeyInfo, error) {
	rows, err := s.DB.Query(ctx, `SELECT id, name, created_at, last_used_at FROM passkeys WHERE user_id = $1 ORDER BY created_at`, user)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (PasskeyInfo, error) {
		var p PasskeyInfo
		var id []byte
		err := r.Scan(&id, &p.Name, &p.Created, &p.LastUsed)
		p.ID = base64.RawURLEncoding.EncodeToString(id)
		return p, err
	})
}

// DeletePasskey removes one of a user's passkeys. The last way to log in
// cannot be removed.
func (s *Service) DeletePasskey(ctx context.Context, u dbq.User, id string) error {
	raw, err := base64.RawURLEncoding.DecodeString(id)
	if err != nil {
		return ErrPasskeyMissing
	}
	return pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		res, err := tx.Exec(ctx, `DELETE FROM passkeys WHERE id = $1 AND user_id = $2`, raw, u.ID)
		if err != nil {
			return err
		}
		if res.RowsAffected() == 0 {
			return ErrPasskeyMissing
		}
		return lastLogin(ctx, tx, u)
	})
}

// lastLogin fails with ErrLastLogin (rolling back tx) if u has no way left
// to log in: no password, passkey or provider account.
func lastLogin(ctx context.Context, tx pgx.Tx, u dbq.User) error {
	var ok bool
	if err := tx.QueryRow(ctx, `SELECT password_hash IS NOT NULL
		OR EXISTS (SELECT 1 FROM passkeys WHERE user_id = $1)
		OR EXISTS (SELECT 1 FROM identities WHERE user_id = $1)
		FROM users WHERE id = $1`, u.ID).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrLastLogin
	}
	return nil
}

// ErrLastLogin means a change would leave the account without a way to log
// in.
var ErrLastLogin = errors.New("auth: this is the last way to log in")
