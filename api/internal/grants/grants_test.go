package grants

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/access"
	"github.com/tellbow/odysgeh/api/internal/dbq"
	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/api/internal/testdb"
)

func TestInvitations(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	user := func(name string, verified bool) dbq.User {
		t.Helper()
		var u dbq.User
		err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale, email_verified_at)
			VALUES ($1 || '@example.ch', $1, initcap($1), 'de', CASE WHEN $2 THEN now() END)
			RETURNING id, email, username, display_name, locale, email_verified_at`, name, verified).
			Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.Locale, &u.EmailVerifiedAt)
		if err != nil {
			t.Fatal(err)
		}
		return u
	}
	owner, bea, carl := user("anna", true), user("bea", true), user("carl", false)
	var jid uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO journeys (owner_id, title) VALUES ($1, 'Via Alpina') RETURNING id`,
		owner.ID).Scan(&jid); err != nil {
		t.Fatal(err)
	}
	rec := &mailer.Recorder{}
	s := &Store{DB: pool, Mail: rec, PublicURL: "https://odysgeh.test"}
	target := Target{Kind: Journey, ID: jid, Title: "Via Alpina"}
	role := func(u dbq.User) access.Role {
		t.Helper()
		r, err := s.RoleOf(ctx, Journey, jid, u)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}

	// By username: effective at once, announced to the account's address.
	if err := s.Invite(ctx, target, owner, Invite{Username: "@bea", Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if role(bea) != access.Viewer {
		t.Errorf("bea: %s", role(bea))
	}
	sent := rec.Sent()
	if len(sent) != 1 || sent[0].To != "bea@example.ch" || !strings.Contains(sent[0].Subject, "Via Alpina") ||
		!strings.Contains(sent[0].Text, "https://odysgeh.test/journeys/"+jid.String()) {
		t.Fatalf("invitation mail %+v", sent)
	}
	// Inviting again changes the role without another e-mail.
	if err := s.Invite(ctx, target, owner, Invite{Username: "bea", Role: "editor"}); err != nil {
		t.Fatal(err)
	}
	if role(bea) != access.Editor || len(rec.Sent()) != 1 {
		t.Errorf("re-invite: role %s, %d mails", role(bea), len(rec.Sent()))
	}

	// By address: applies only to a verified account with that address.
	if err := s.Invite(ctx, target, owner, Invite{Email: "Carl@Example.CH", Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if role(carl) != access.None {
		t.Errorf("unverified carl: %s", role(carl))
	}
	if _, err := pool.Exec(ctx, `UPDATE users SET email_verified_at = now() WHERE id = $1`, carl.ID); err != nil {
		t.Fatal(err)
	}
	carl.EmailVerifiedAt = new(owner.CreatedAt)
	if role(carl) != access.Viewer {
		t.Errorf("verified carl: %s", role(carl))
	}

	for _, tc := range []struct {
		in   Invite
		want error
	}{
		{Invite{Username: "nobody", Role: "viewer"}, ErrNoUser},
		{Invite{Username: "anna", Role: "viewer"}, ErrSelf},
		{Invite{Email: "ANNA@example.ch", Role: "viewer"}, ErrSelf},
	} {
		if err := s.Invite(ctx, target, owner, tc.in); !errors.Is(err, tc.want) {
			t.Errorf("%+v: %v, want %v", tc.in, err, tc.want)
		}
	}

	list, err := s.List(ctx, target)
	if err != nil || len(list) != 2 || list[0].Username != "bea" || list[0].Role != "editor" || list[1].Email != "carl@example.ch" {
		t.Fatalf("list %+v %v", list, err)
	}
	if err := s.SetRole(ctx, target, uuid.MustParse(list[1].ID), "editor"); err != nil || role(carl) != access.Editor {
		t.Errorf("set role: %v, %s", err, role(carl))
	}
	if err := s.Delete(ctx, target, uuid.MustParse(list[0].ID)); err != nil || role(bea) != access.None {
		t.Errorf("delete: %v, %s", err, role(bea))
	}
	if err := s.Delete(ctx, target, uuid.MustParse(list[0].ID)); !errors.Is(err, ErrNotFound) {
		t.Errorf("delete twice: %v", err)
	}
	if err := s.Leave(ctx, target, carl); err != nil || role(carl) != access.None {
		t.Errorf("leave: %v, %s", err, role(carl))
	}

	// The limit counts grants per item.
	for i := range MaxPerItem {
		if err := s.Invite(ctx, target, owner, Invite{Email: uuid.NewString()[:8] + "@example.ch", Role: "viewer"}); err != nil {
			t.Fatalf("invite %d: %v", i, err)
		}
	}
	if err := s.Invite(ctx, target, owner, Invite{Email: "one-more@example.ch", Role: "viewer"}); !errors.Is(err, ErrTooMany) {
		t.Errorf("over the limit: %v", err)
	}
}
