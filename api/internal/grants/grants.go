// Package grants shares routes, journeys and collections with other people: by account
// (username) or by e-mail address. An e-mail grant applies to whoever signs
// in with that verified address, so invitations work before the invitee has
// an account and never reveal whether an address is registered.
package grants

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/access"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

// MaxPerItem bounds the grants on one route, journey or collection.
const MaxPerItem = 50

// Errors of invitations.
var (
	ErrNotFound = errors.New("grant not found")
	ErrNoUser   = errors.New("no user with this name")
	ErrSelf     = errors.New("you already own this")
	ErrTooMany  = errors.New("too many people have access already")
)

// Kind is what a grant is on.
type Kind string

// Kinds of shareable items.
const (
	Route      Kind = "route"
	Journey    Kind = "journey"
	Collection Kind = "collection"
)

func (k Kind) column() string { return string(k) + "_id" }

func (k Kind) path() string { return "/" + string(k) + "s/" }

// Target is the item a grant is on.
type Target struct {
	Kind  Kind
	ID    uuid.UUID
	Title string
}

// Grant is one person's access, as the owner sees it.
type Grant struct {
	ID   string `json:"id" format:"uuid"`
	Role string `json:"role" enum:"viewer,editor"`
	// Username and DisplayName for grants to an account.
	Username    string `json:"username,omitempty"`
	DisplayName string `json:"display_name,omitempty"`
	// Email for invitations by address (whether or not it has an account).
	Email     string    `json:"email,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// Invite names who to invite: a username or an e-mail address.
type Invite struct {
	Username string
	Email    string
	Role     string // viewer, editor
}

// Store reads and writes grants and sends invitation e-mails.
type Store struct {
	DB        *pgxpool.Pool
	Mail      mailer.Sender
	PublicURL string
}

// Grantee identifies a user for grant matching.
func Grantee(u dbq.User) (id uuid.UUID, verifiedEmail string) {
	if u.EmailVerifiedAt != nil {
		verifiedEmail = u.Email
	}
	return u.ID, verifiedEmail
}

// RoleOf returns the best role the grants on an item give the user.
func (s *Store) RoleOf(ctx context.Context, kind Kind, id uuid.UUID, u dbq.User) (access.Role, error) {
	uid, email := Grantee(u)
	var role *string // NULL without a grant
	err := s.DB.QueryRow(ctx, `SELECT max(role)::text FROM grants
		WHERE `+kind.column()+` = $1 AND (user_id = $2 OR (email = $3 AND $3 <> ''))`, id, uid, email).Scan(&role)
	if err != nil {
		return access.None, fmt.Errorf("grants: role: %w", err)
	}
	if role == nil {
		return access.None, nil
	}
	return access.ParseGrant(*role), nil
}

// List returns the grants on an item, oldest first.
func (s *Store) List(ctx context.Context, t Target) ([]Grant, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT g.id, g.role, coalesce(u.username, ''), coalesce(u.display_name, ''), coalesce(g.email, ''), g.created_at
		FROM grants g LEFT JOIN users u ON u.id = g.user_id
		WHERE g.`+t.Kind.column()+` = $1 ORDER BY g.created_at`, t.ID)
	if err != nil {
		return nil, fmt.Errorf("grants: list: %w", err)
	}
	defer rows.Close()
	out := []Grant{}
	for rows.Next() {
		var g Grant
		var id uuid.UUID
		if err := rows.Scan(&id, &g.Role, &g.Username, &g.DisplayName, &g.Email, &g.CreatedAt); err != nil {
			return nil, err
		}
		g.ID = id.String()
		out = append(out, g)
	}
	return out, rows.Err()
}

// Invite grants access or changes the role of an existing grant. New grants
// are announced by e-mail; delivery failures are logged, not returned.
func (s *Store) Invite(ctx context.Context, t Target, owner dbq.User, in Invite) error {
	g, err := s.grantee(ctx, owner, in)
	if err != nil {
		return err
	}
	var inserted bool
	err = pgx.BeginFunc(ctx, s.DB, func(tx pgx.Tx) error {
		// Serialize invitations per item so the limit holds.
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, t.ID.String()); err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM grants WHERE `+t.Kind.column()+` = $1`, t.ID).Scan(&n); err != nil {
			return err
		}
		err := tx.QueryRow(ctx, `
			INSERT INTO grants (`+t.Kind.column()+`, user_id, email, role, invited_by)
			VALUES ($1, $2, $3, $4::grant_role, $5)
			ON CONFLICT ON CONSTRAINT grants_target_grantee_key DO UPDATE SET role = excluded.role
			RETURNING xmax = 0`, t.ID, g.userID, g.email, in.Role, owner.ID).Scan(&inserted)
		if err != nil {
			return err
		}
		if inserted && n >= MaxPerItem {
			return ErrTooMany // rolls back
		}
		return nil
	})
	if err != nil {
		return err
	}
	if inserted {
		s.announce(ctx, g, owner, t, in.Role)
	}
	return nil
}

// invitee is who a grant goes to: an account or an address, and who
// receives the invitation e-mail, in which language.
type invitee struct {
	userID     *uuid.UUID
	email      *string
	to, locale string
}

func (s *Store) grantee(ctx context.Context, owner dbq.User, in Invite) (invitee, error) {
	g := invitee{locale: owner.Locale}
	switch {
	case in.Username != "":
		var id uuid.UUID
		var uEmail, uLocale string
		err := s.DB.QueryRow(ctx, `SELECT id, email, locale FROM users WHERE username = $1 AND banned_at IS NULL`,
			strings.TrimPrefix(strings.TrimSpace(in.Username), "@")).Scan(&id, &uEmail, &uLocale)
		if errors.Is(err, pgx.ErrNoRows) {
			return g, ErrNoUser
		}
		if err != nil {
			return g, err
		}
		if id == owner.ID {
			return g, ErrSelf
		}
		g.userID, g.to, g.locale = &id, uEmail, uLocale
	default:
		addr := strings.ToLower(strings.TrimSpace(in.Email))
		if strings.EqualFold(addr, owner.Email) {
			return g, ErrSelf
		}
		g.email, g.to = &addr, addr
		// Write in the invitee's language if the address has a verified account.
		var l string
		if err := s.DB.QueryRow(ctx, `SELECT locale FROM users WHERE email = $1 AND email_verified_at IS NOT NULL`,
			addr).Scan(&l); err == nil {
			g.locale = l
		}
	}
	return g, nil
}

// announce sends the invitation e-mail; failures are logged.
func (s *Store) announce(ctx context.Context, g invitee, owner dbq.User, t Target, role string) {
	m := inviteMail(g.to, g.locale, owner, t, role, s.PublicURL+t.Kind.path()+t.ID.String())
	if err := s.Mail.Send(ctx, m); err != nil {
		slog.ErrorContext(ctx, "invitation e-mail", "err", err)
	}
}

// SetRole changes the role of a grant on the item.
func (s *Store) SetRole(ctx context.Context, t Target, grantID uuid.UUID, role string) error {
	res, err := s.DB.Exec(ctx, `UPDATE grants SET role = $3::grant_role WHERE id = $2 AND `+t.Kind.column()+` = $1`,
		t.ID, grantID, role)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Delete removes a grant from the item.
func (s *Store) Delete(ctx context.Context, t Target, grantID uuid.UUID) error {
	res, err := s.DB.Exec(ctx, `DELETE FROM grants WHERE id = $2 AND `+t.Kind.column()+` = $1`, t.ID, grantID)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Leave removes the user's own grants on the item (by account and address).
func (s *Store) Leave(ctx context.Context, t Target, u dbq.User) error {
	uid, email := Grantee(u)
	res, err := s.DB.Exec(ctx, `DELETE FROM grants WHERE `+t.Kind.column()+` = $1
		AND (user_id = $2 OR (email = $3 AND $3 <> ''))`, t.ID, uid, email)
	if err != nil {
		return err
	}
	if res.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func inviteMail(to, locale string, owner dbq.User, t Target, role, link string) mailer.Message {
	switch locale {
	case "fr":
		what := map[Kind]string{Route: "l'itinéraire", Journey: "la randonnée par étapes", Collection: "la collection"}[t.Kind]
		verb := map[string]string{"viewer": "consulter", "editor": "planifier ensemble"}[role]
		return mailer.Message{
			To:      to,
			Subject: fmt.Sprintf("%s a partagé « %s » avec toi", owner.DisplayName, t.Title),
			Text: fmt.Sprintf("Bonjour\n\n%s (@%s) t'invite à %s %s « %s » sur Alvyo :\n\n%s\n\n"+
				"Pas encore de compte ? Inscris-toi avec cette adresse e-mail (%s) ; une fois confirmée, tu trouveras "+
				"l'invitation sous « Partagé avec moi ».\n", owner.DisplayName, owner.Username, verb, what, t.Title, link, to),
		}
	case "it":
		what := map[Kind]string{Route: "il percorso", Journey: "il trekking a tappe", Collection: "la raccolta"}[t.Kind]
		verb := map[string]string{"viewer": "vedere", "editor": "pianificare insieme"}[role]
		return mailer.Message{
			To:      to,
			Subject: fmt.Sprintf("%s ha condiviso «%s» con te", owner.DisplayName, t.Title),
			Text: fmt.Sprintf("Ciao\n\n%s (@%s) ti invita a %s %s «%s» su Alvyo:\n\n%s\n\n"+
				"Non hai ancora un account? Registrati con questo indirizzo e-mail (%s); dopo la conferma troverai "+
				"l'invito in «Condivisi con me».\n", owner.DisplayName, owner.Username, verb, what, t.Title, link, to),
		}
	case "de":
		what := map[Kind]string{Route: "die Route", Journey: "die Etappentour", Collection: "die Sammlung"}[t.Kind]
		verb := map[string]string{"viewer": "anzusehen", "editor": "mitzuplanen"}[role]
		return mailer.Message{
			To:      to,
			Subject: fmt.Sprintf("%s hat «%s» mit dir geteilt", owner.DisplayName, t.Title),
			Text: fmt.Sprintf("Hallo\n\n%s (@%s) lädt dich ein, %s «%s» auf Alvyo %s:\n\n%s\n\n"+
				"Noch kein Konto? Registriere dich mit dieser E-Mail-Adresse (%s); nach der Bestätigung "+
				"findest du die Einladung unter «Mit mir geteilt».\n", owner.DisplayName, owner.Username, what, t.Title, verb, link, to),
		}
	}
	what := map[Kind]string{Route: "the route", Journey: "the journey", Collection: "the collection"}[t.Kind]
	verb := map[string]string{"viewer": "view", "editor": "plan"}[role]
	return mailer.Message{
		To:      to,
		Subject: fmt.Sprintf("%s shared “%s” with you", owner.DisplayName, t.Title),
		Text: fmt.Sprintf("Hi\n\n%s (@%s) invites you to %s %s “%s” on Alvyo:\n\n%s\n\n"+
			"No account yet? Sign up with this e-mail address (%s); once it is confirmed, "+
			"the invitation appears under “Shared with me”.\n", owner.DisplayName, owner.Username, verb, what, t.Title, link, to),
	}
}
