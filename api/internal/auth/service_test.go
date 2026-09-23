package auth

import (
	"context"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/api/internal/testdb"
)

var tokenRe = regexp.MustCompile(`token=([A-Za-z0-9_-]+)`)

func newService(t *testing.T) (*Service, *mailer.Recorder, *time.Time) {
	now := time.Now()
	rec := &mailer.Recorder{}
	return &Service{
		DB: testdb.New(t), Mail: rec, PublicURL: "https://odysgeh.test",
		Now: func() time.Time { return now },
	}, rec, &now
}

func TestSessionSlides(t *testing.T) {
	ctx := context.Background()
	svc, _, now := newService(t)
	_, sess, err := svc.Signup(ctx, SignupInput{Email: "a@example.ch", Username: "anna", DisplayName: "Anna", Password: "0123456789", Locale: "de"}, "test")
	if err != nil {
		t.Fatal(err)
	}

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
}

func TestResetPasswordEndsSessions(t *testing.T) {
	ctx := context.Background()
	svc, rec, _ := newService(t)
	_, sess, err := svc.Signup(ctx, SignupInput{Email: "b@example.ch", Username: "beat", DisplayName: "Beat", Password: "0123456789", Locale: "en"}, "")
	if err != nil {
		t.Fatal(err)
	}
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

func TestForgotPasswordUnknownEmail(t *testing.T) {
	svc, rec, _ := newService(t)
	if err := svc.ForgotPassword(context.Background(), "nobody@example.ch"); err != nil {
		t.Fatal(err)
	}
	if len(rec.Sent()) != 0 {
		t.Error("mail sent for unknown address")
	}
}
