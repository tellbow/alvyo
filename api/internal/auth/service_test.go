package auth

import (
	"context"
	"errors"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/testdb"
)

var tokenRe = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

func newService(t *testing.T) (*Service, *mailer.Recorder, *time.Time) {
	now := time.Now()
	rec := &mailer.Recorder{}
	return &Service{
		DB: testdb.New(t), Mail: rec, PublicURL: "https://alvyo.test",
		Now: func() time.Time { return now },
	}, rec, &now
}

// signedUp signs up and confirms the address with the e-mailed link, which
// logs in.
func signedUp(t *testing.T, svc *Service, rec *mailer.Recorder, in SignupInput) Session {
	t.Helper()
	ctx := context.Background()
	if err := svc.Signup(ctx, in); err != nil {
		t.Fatal(err)
	}
	msgs := rec.Sent()
	_, sess, err := svc.VerifyEmail(ctx, tokenRe.FindStringSubmatch(msgs[len(msgs)-1].Text)[1], "test")
	if err != nil {
		t.Fatal(err)
	}
	return sess
}

func TestSignupLogsInOnceConfirmed(t *testing.T) {
	ctx := context.Background()
	svc, rec, _ := newService(t)
	in := SignupInput{Email: "e@example.ch", Username: "eva", DisplayName: "Eva", Password: "0123456789", Locale: "de"}
	if err := svc.Signup(ctx, in); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Login(ctx, "eva", "0123456789", ""); !errors.Is(err, ErrUnverified) {
		t.Errorf("login before confirming: %v", err)
	}
	token := tokenRe.FindStringSubmatch(rec.Sent()[0].Text)[1]
	if u, err := svc.VerificationFor(ctx, token); err != nil || u.Username != "eva" {
		t.Errorf("whose link: %v %v", u.Username, err)
	}
	if _, _, err := svc.VerifyEmail(ctx, token, ""); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Login(ctx, "eva", "0123456789", ""); err != nil {
		t.Errorf("login once confirmed: %v", err)
	}

	// The same address again: no error, no account, an e-mail to its owner.
	if err := svc.Signup(ctx, SignupInput{Email: "e@example.ch", Username: "mallory", DisplayName: "M", Password: "0123456789", Locale: "en"}); err != nil {
		t.Errorf("signup with a taken address: %v", err)
	}
	if last := rec.Sent()[len(rec.Sent())-1]; last.To != "e@example.ch" || last.Subject != "Alvyo: Du hast schon ein Konto" {
		t.Errorf("e-mail to the owner: %+v", last)
	}
	if _, err := svc.q().GetUserByLogin(ctx, "mallory"); err == nil {
		t.Error("an account for the taken address")
	}
	if err := svc.Signup(ctx, SignupInput{Email: "f@example.ch", Username: "eva", DisplayName: "F", Password: "0123456789", Locale: "de"}); !errors.Is(err, ErrUsernameTaken) {
		t.Errorf("taken username: %v", err)
	}
}

func TestSessionSlides(t *testing.T) {
	ctx := context.Background()
	svc, rec, now := newService(t)
	sess := signedUp(t, svc, rec, SignupInput{Email: "a@example.ch", Username: "anna", DisplayName: "Anna", Password: "0123456789", Locale: "de"})

	// Same day: no extension.
	if _, ext, err := svc.SessionUser(ctx, sess.Token); err != nil || ext != nil {
		t.Fatalf("fresh session: ext=%v err=%v", ext, err)
	}
	// Two days later: extended to now + 30 days.
	*now = now.Add(48 * time.Hour)
	_, ext, err := svc.SessionUser(ctx, sess.Token)
	if err != nil || ext == nil || ext.Sub(*now) != SessionTTL {
		t.Fatalf("after 2 days: ext=%v err=%v", ext, err)
	}
	// Used every day, it still ends 180 days after the login.
	for range 200 {
		*now = now.Add(24 * time.Hour)
		if _, _, err := svc.SessionUser(ctx, sess.Token); err != nil {
			break
		}
	}
	if _, _, err := svc.SessionUser(ctx, sess.Token); !errors.Is(err, ErrNoSession) {
		t.Errorf("after 200 days of use: %v", err)
	}
}

func TestResetPasswordEndsSessions(t *testing.T) {
	ctx := context.Background()
	svc, rec, _ := newService(t)
	sess := signedUp(t, svc, rec, SignupInput{Email: "b@example.ch", Username: "beat", DisplayName: "Beat", Password: "0123456789", Locale: "en"})
	if err := svc.ForgotPassword(ctx, "b@example.ch"); err != nil {
		t.Fatal(err)
	}
	msgs := rec.Sent()
	reset := tokenRe.FindStringSubmatch(msgs[len(msgs)-1].Text)[1]

	if err := svc.ResetPassword(ctx, reset, "new-password-123"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.SessionUser(ctx, sess.Token); !errors.Is(err, ErrNoSession) {
		t.Errorf("old session still valid: %v", err)
	}
	if err := svc.ResetPassword(ctx, reset, "another-password"); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("token reused: %v", err)
	}
	u, _, err := svc.Login(ctx, "beat", "new-password-123", "")
	if err != nil {
		t.Fatalf("login with new password: %v", err)
	}
	if u.EmailVerifiedAt == nil {
		t.Error("reset via e-mail should verify the address")
	}
}

// Someone signs up through a provider with another person's address, which
// the provider does not vouch for. When the address's owner resets the
// password, the provider must no longer log in.
func TestResetPasswordDropsIdentities(t *testing.T) {
	ctx := context.Background()
	svc, rec, _ := newService(t)
	stranger := Identity{Provider: "test", Subject: "s-1", Email: "c@example.ch"}
	allow := func() bool { return true }
	if _, _, err := svc.IdentityLogin(ctx, stranger, "de", "", allow); err != nil {
		t.Fatal(err)
	}
	if err := svc.ForgotPassword(ctx, "c@example.ch"); err != nil {
		t.Fatal(err)
	}
	msgs := rec.Sent()
	reset := tokenRe.FindStringSubmatch(msgs[len(msgs)-1].Text)[1]
	if err := svc.ResetPassword(ctx, reset, "owner-password-1"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.IdentityLogin(ctx, stranger, "de", "", allow); !errors.Is(err, ErrEmailTaken) {
		t.Errorf("the stranger's provider login after the reset: %v, want ErrEmailTaken", err)
	}

	// Also once the address was confirmed: a reset takes the account over,
	// providers go (they may have been added by whoever
	// confirmed a stranger's address by mistake).
	owner := Identity{Provider: "test", Subject: "o-1", Email: "d@example.ch", EmailVerified: true}
	if _, _, err := svc.IdentityLogin(ctx, owner, "de", "", allow); err != nil {
		t.Fatal(err)
	}
	if err := svc.ForgotPassword(ctx, "d@example.ch"); err != nil {
		t.Fatal(err)
	}
	msgs = rec.Sent()
	reset = tokenRe.FindStringSubmatch(msgs[len(msgs)-1].Text)[1]
	if err := svc.ResetPassword(ctx, reset, "owner-password-2"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.IdentityLogin(ctx, owner, "de", "", allow); !errors.Is(err, ErrEmailTaken) {
		t.Errorf("provider login after the reset: %v, want ErrEmailTaken", err)
	}
}

func TestForgotPasswordUnknownEmail(t *testing.T) {
	svc, rec, _ := newService(t)
	if err := svc.ForgotPassword(context.Background(), "nobody@example.ch"); err != nil {
		t.Fatal(err)
	}
	if len(rec.Sent()) != 0 {
		t.Error("mail sent for unknown address")
	}
}

// The 21st sign-in with the same name still gets an account (feedback
// issue 35).
func TestIdentityLoginCommonName(t *testing.T) {
	ctx := context.Background()
	svc, _, _ := newService(t)
	allow := func() bool { return true }
	seen := map[string]bool{}
	for i := range 23 {
		id := Identity{Provider: "test", Subject: "s-" + strconv.Itoa(i), Email: "info@example" + strconv.Itoa(i) + ".ch"}
		u, _, err := svc.IdentityLogin(ctx, id, "de", "", allow)
		if err != nil {
			t.Fatalf("sign-in %d: %v", i+1, err)
		}
		if seen[u.Username] || !strings.HasPrefix(u.Username, "info") {
			t.Errorf("sign-in %d: username %q", i+1, u.Username)
		}
		seen[u.Username] = true
	}
}
