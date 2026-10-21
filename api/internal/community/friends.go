package community

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

// Friend is how the viewer and another user stand as friends.
type Friend string

// How two users stand as friends.
const (
	NoFriend  Friend = "none"
	Requested Friend = "requested" // the viewer asked
	Incoming  Friend = "incoming"  // the other asked the viewer
	Friends   Friend = "friends"
)

// friendState is the SQL for how $1 and $2 stand as friends.
const friendState = `coalesce((SELECT CASE WHEN accepted_at IS NOT NULL THEN 'friends'
		WHEN requester_id = $1 THEN 'requested' ELSE 'incoming' END
	FROM friendships WHERE (requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1)), 'none')`

// FriendState returns how viewer and other stand (viewer may be uuid.Nil).
func (s *Store) FriendState(ctx context.Context, viewer, other uuid.UUID) (Friend, error) {
	var f Friend
	err := s.DB.QueryRow(ctx, `SELECT `+friendState, viewer, other).Scan(&f)
	return f, err
}

// notBlocked returns ErrBlocked if one of the two blocked the other.
func notBlocked(ctx context.Context, tx pgx.Tx, a, b uuid.UUID) error {
	var blocked bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM blocks
		WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`, a, b).Scan(&blocked); err != nil {
		return err
	}
	if blocked {
		return ErrBlocked
	}
	return nil
}

// RequestFriend asks other to be friends and tells them; if other asked
// first, they are friends now.
func (s *Store) RequestFriend(ctx context.Context, from dbq.User, other uuid.UUID) error {
	if from.ID == other {
		return ErrForbidden
	}
	var asked bool
	err := s.pairTx(ctx, from.ID, other, func(tx pgx.Tx) error {
		if err := notBlocked(ctx, tx, from.ID, other); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `UPDATE friendships SET accepted_at = now()
			WHERE requester_id = $2 AND addressee_id = $1 AND accepted_at IS NULL`, from.ID, other)
		if err != nil || tag.RowsAffected() > 0 {
			return err
		}
		tag, err = tx.Exec(ctx, `INSERT INTO friendships (requester_id, addressee_id) VALUES ($1, $2)
			ON CONFLICT DO NOTHING`, from.ID, other)
		asked = tag.RowsAffected() > 0 // or asked before, or friends already
		return err
	})
	if err != nil || !asked {
		return err
	}
	s.notifyFriendRequest(ctx, from, other)
	return nil
}

// Unfriend ends a friendship, or withdraws or declines a request.
func (s *Store) Unfriend(ctx context.Context, a, b uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `DELETE FROM friendships
		WHERE (requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1)`, a, b)
	return err
}

// FriendRef is a user with how the viewer stands with them.
type FriendRef struct {
	Username    string    `json:"username"`
	DisplayName string    `json:"display_name"`
	Friend      Friend    `json:"friend" enum:"none,requested,incoming,friends"`
	Since       time.Time `json:"since" doc:"When they became friends, or were asked"`
}

// FriendLists are a user's friends and open requests.
type FriendLists struct {
	Friends  []FriendRef `json:"friends" doc:"By name"`
	Incoming []FriendRef `json:"incoming" doc:"Asking the user, newest first"`
	Outgoing []FriendRef `json:"outgoing" doc:"Asked by the user, newest first"`
}

// FriendLists returns user's friends and the requests to and from them;
// banned users are left out.
func (s *Store) FriendLists(ctx context.Context, user uuid.UUID) (FriendLists, error) {
	rows, err := s.DB.Query(ctx, `SELECT u.username, u.display_name,
			CASE WHEN f.accepted_at IS NOT NULL THEN 'friends' WHEN f.requester_id = $1 THEN 'requested' ELSE 'incoming' END,
			coalesce(f.accepted_at, f.created_at)
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
		WHERE (f.requester_id = $1 OR f.addressee_id = $1) AND u.banned_at IS NULL
		ORDER BY coalesce(f.accepted_at, f.created_at) DESC`, user)
	if err != nil {
		return FriendLists{}, err
	}
	refs, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (FriendRef, error) {
		var f FriendRef
		return f, r.Scan(&f.Username, &f.DisplayName, &f.Friend, &f.Since)
	})
	if err != nil {
		return FriendLists{}, err
	}
	l := FriendLists{Friends: []FriendRef{}, Incoming: []FriendRef{}, Outgoing: []FriendRef{}}
	for _, f := range refs {
		switch f.Friend {
		case Friends:
			l.Friends = append(l.Friends, f)
		case Incoming:
			l.Incoming = append(l.Incoming, f)
		default:
			l.Outgoing = append(l.Outgoing, f)
		}
	}
	return l, nil
}

// IncomingRequests counts the requests waiting for user.
func (s *Store) IncomingRequests(ctx context.Context, user uuid.UUID) (int, error) {
	var n int
	err := s.DB.QueryRow(ctx, `SELECT count(*) FROM friendships f JOIN users u ON u.id = f.requester_id
		WHERE f.addressee_id = $1 AND f.accepted_at IS NULL AND u.banned_at IS NULL`, user).Scan(&n)
	return n, err
}

// SearchUsers finds public profiles by the start of the username or a part
// of the display name, without the viewer, banned users and those either
// blocked; at most 20, by username.
func (s *Store) SearchUsers(ctx context.Context, viewer uuid.UUID, q string) ([]FriendRef, error) {
	like := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(strings.TrimPrefix(strings.TrimSpace(q), "@"))
	rows, err := s.DB.Query(ctx, `SELECT u.username, u.display_name, `+strings.ReplaceAll(friendState, "$2", "u.id")+`, u.created_at
		FROM users u
		WHERE u.profile_public AND u.banned_at IS NULL AND u.id <> $1
			AND (u.username ILIKE $2 || '%' OR u.display_name ILIKE '%' || $2 || '%')
			AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = u.id)
				OR (b.blocker_id = u.id AND b.blocked_id = $1))
		ORDER BY u.username LIMIT 20`, viewer, like)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (FriendRef, error) {
		var f FriendRef
		return f, r.Scan(&f.Username, &f.DisplayName, &f.Friend, &f.Since)
	})
}

// FriendToken returns user's invite link token, made the first time.
func (s *Store) FriendToken(ctx context.Context, user uuid.UUID) (string, error) {
	var t string
	err := s.DB.QueryRow(ctx, `UPDATE users SET friend_token = coalesce(friend_token, $2) WHERE id = $1
		RETURNING friend_token`, user, newFriendToken()).Scan(&t)
	return t, err
}

// RotateFriendToken gives user a new invite link; the old one stops working.
func (s *Store) RotateFriendToken(ctx context.Context, user uuid.UUID) (string, error) {
	var t string
	err := s.DB.QueryRow(ctx, `UPDATE users SET friend_token = $2 WHERE id = $1 RETURNING friend_token`,
		user, newFriendToken()).Scan(&t)
	return t, err
}

func newFriendToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// Inviter returns whose invite link token is.
func (s *Store) Inviter(ctx context.Context, token string) (uuid.UUID, UserRef, error) {
	var id uuid.UUID
	var u UserRef
	err := s.DB.QueryRow(ctx, `SELECT id, username, display_name FROM users
		WHERE friend_token = $1 AND banned_at IS NULL`, token).Scan(&id, &u.Username, &u.DisplayName)
	if errors.Is(err, pgx.ErrNoRows) {
		return id, u, ErrNotFound
	}
	return id, u, err
}

// AcceptInvite makes user and the owner of the invite link token friends:
// sending the link was their consent.
func (s *Store) AcceptInvite(ctx context.Context, user uuid.UUID, token string) (UserRef, error) {
	inviter, ref, err := s.Inviter(ctx, token)
	if err != nil {
		return ref, err
	}
	if inviter == user {
		return ref, ErrForbidden
	}
	return ref, s.pairTx(ctx, user, inviter, func(tx pgx.Tx) error {
		if err := notBlocked(ctx, tx, user, inviter); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO friendships (requester_id, addressee_id, accepted_at) VALUES ($1, $2, now())
			ON CONFLICT (least(requester_id, addressee_id), greatest(requester_id, addressee_id))
			DO UPDATE SET accepted_at = coalesce(friendships.accepted_at, now())`, user, inviter)
		return err
	})
}

func (s *Store) notifyFriendRequest(ctx context.Context, from dbq.User, to uuid.UUID) {
	r, ok := s.wants(ctx, to, "notify_follows")
	if !ok || !s.due(ctx, to, "friends") {
		return
	}
	link := s.PublicURL + "/friends"
	subject, text := fmt.Sprintf("%s would like to be friends", from.DisplayName),
		fmt.Sprintf("Hi\n\n%s (@%s) would like to be your friend on Alvyo. Accept or decline:\n\n%s\n\n"+
			"Notification settings: %s/account\n", from.DisplayName, from.Username, link, s.PublicURL)
	switch r.locale {
	case "de":
		subject, text = fmt.Sprintf("%s möchte mit dir befreundet sein", from.DisplayName),
			fmt.Sprintf("Hallo\n\n%s (@%s) möchte auf Alvyo mit dir befreundet sein. Annehmen oder ablehnen:\n\n%s\n\n"+
				"Benachrichtigungen einstellen: %s/account\n", from.DisplayName, from.Username, link, s.PublicURL)
	case "fr":
		subject, text = fmt.Sprintf("%s aimerait être ton ami·e", from.DisplayName),
			fmt.Sprintf("Bonjour\n\n%s (@%s) aimerait être ton ami·e sur Alvyo. Accepter ou refuser :\n\n%s\n\n"+
				"Régler les notifications : %s/account\n", from.DisplayName, from.Username, link, s.PublicURL)
	case "it":
		subject, text = fmt.Sprintf("%s vorrebbe essere tuo amico", from.DisplayName),
			fmt.Sprintf("Ciao\n\n%s (@%s) vorrebbe essere tuo amico su Alvyo. Accetta o rifiuta:\n\n%s\n\n"+
				"Impostazioni delle notifiche: %s/account\n", from.DisplayName, from.Username, link, s.PublicURL)
	}
	s.send(ctx, mailer.Message{To: r.email, Subject: subject, Text: text})
}
