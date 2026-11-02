package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"maps"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/bugs"
	"github.com/tellbow/alvyo/api/internal/spam"
)

// withProof is the body with a new challenge answered, as the forms send it.
func withProof(t *testing.T, c *client, body map[string]any) map[string]any {
	t.Helper()
	code, raw := c.do("POST", "/api/v1/challenge", nil)
	if code != http.StatusOK {
		t.Fatalf("challenge: %d %s", code, raw)
	}
	var ch struct {
		Challenge string `json:"challenge"`
		Bits      int    `json:"bits"`
	}
	if err := json.Unmarshal(raw, &ch); err != nil {
		t.Fatal(err)
	}
	out := maps.Clone(body)
	out["challenge"], out["nonce"] = ch.Challenge, answerChallenge(ch.Challenge, ch.Bits)
	return out
}

func answerChallenge(challenge string, bits int) string {
next:
	for n := 0; ; n++ {
		sum := sha256.Sum256(fmt.Appendf(nil, "%s:%d", challenge, n))
		for i := range bits {
			if sum[i>>3]&(0x80>>(i&7)) != 0 {
				continue next
			}
		}
		return strconv.Itoa(n)
	}
}

// The forms' protection, on every form: no answer, no entry; an answer once;
// the trap stays empty.
func TestSpamProofOnForms(t *testing.T) {
	s := newTestServerWith(t, func(d *Deps) {
		d.Spam = spam.Relaxed()
		d.Bugs = &bugs.Store{DB: d.DB}
	})
	owner := s.client(t)
	if code, _ := owner.do("POST", "/api/v1/auth/signup", signupBody("x", "x")); code != http.StatusUnprocessableEntity {
		t.Errorf("invalid input: %d", code)
	}
	body := signupBody("anna@example.ch", "anna")
	if code, raw := owner.do("POST", "/api/v1/auth/signup", body); code != http.StatusUnprocessableEntity || !strings.Contains(string(raw), "body.challenge") {
		t.Errorf("signup without an answer: %d %s", code, raw)
	}
	proved := withProof(t, owner, body)
	if code, raw := owner.do("POST", "/api/v1/auth/signup", proved); code != http.StatusAccepted {
		t.Fatalf("signup: %d %s", code, raw)
	}
	again := maps.Clone(proved)
	again["email"], again["username"] = "bea@example.ch", "bea"
	if code, _ := owner.do("POST", "/api/v1/auth/signup", again); code != http.StatusUnprocessableEntity {
		t.Errorf("the same answer again: %d", code)
	}
	trapped := withProof(t, owner, signupBody("bot@example.ch", "bot"))
	trapped["website"] = "http://spam"
	if code, _ := owner.do("POST", "/api/v1/auth/signup", trapped); code != http.StatusBadRequest {
		t.Errorf("the trap: %d", code)
	}

	// Logged in, the address confirmed.
	msgs := s.mail.Sent()
	token := mailToken.FindStringSubmatch(msgs[len(msgs)-1].Text)[1]
	if code, raw := owner.do("POST", "/api/v1/auth/verify-email", map[string]any{"token": token}); code != http.StatusOK {
		t.Fatalf("verify: %d %s", code, raw)
	}
	_, created := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "public"))
	var route savedRoute
	if err := json.Unmarshal(created, &route); err != nil {
		t.Fatal(err)
	}
	routeID := route.ID
	if code, raw := s.client(t).do("POST", "/api/v1/auth/signup", withProof(t, owner, signupBody("cleo@example.ch", "cleo"))); code != http.StatusAccepted {
		t.Fatalf("someone to report: %d %s", code, raw)
	}
	for _, f := range []struct {
		name, path string
		body       map[string]any
		want       int
	}{
		{"comment", "/api/v1/routes/" + routeID + "/comments", map[string]any{"body": "Schön"}, http.StatusOK},
		{"report", "/api/v1/reports", map[string]any{"kind": "user", "username": "cleo", "reason": "spam"}, http.StatusNoContent},
		{"bug report", "/api/v1/bug-reports", map[string]any{"description": "Leer", "place": "/", "version": "1", "platform": "web"}, http.StatusCreated},
	} {
		if code, _ := owner.do("POST", f.path, f.body); code != http.StatusUnprocessableEntity {
			t.Errorf("%s without an answer: %d", f.name, code)
		}
		trapped := withProof(t, owner, f.body)
		trapped["website"] = "http://spam"
		if code, _ := owner.do("POST", f.path, trapped); code != http.StatusBadRequest {
			t.Errorf("%s, the trap: %d", f.name, code)
		}
		if code, raw := owner.do("POST", f.path, withProof(t, owner, f.body)); code != f.want {
			t.Errorf("%s: %d %s", f.name, code, raw)
		}
	}
}

func TestSignupWithoutAMailbox(t *testing.T) {
	s := newTestServerWith(t, func(d *Deps) {
		d.Spam = spam.Relaxed()
		d.Spam.Mailbox = func(_ context.Context, email string) bool { return !strings.HasSuffix(email, "@gone.example") }
	})
	c := s.client(t)
	code, raw := c.do("POST", "/api/v1/auth/signup", withProof(t, c, signupBody("a@gone.example", "anna")))
	if code != http.StatusUnprocessableEntity || !strings.Contains(string(raw), "body.email") {
		t.Errorf("no mailbox: %d %s", code, raw)
	}
	if len(s.mail.Sent()) != 0 {
		t.Error("a mail went out")
	}
	if code, raw := c.do("POST", "/api/v1/auth/signup", withProof(t, c, signupBody("a@example.ch", "anna"))); code != http.StatusAccepted {
		t.Errorf("a mailbox: %d %s", code, raw)
	}
}

// The default is the real thing: a server that was not told otherwise checks.
func TestSpamGuardOnByDefault(t *testing.T) {
	s := newTestServerWith(t, func(d *Deps) { d.Spam = nil })
	if code, _ := s.client(t).do("POST", "/api/v1/auth/signup", signupBody("a@example.ch", "anna")); code != http.StatusUnprocessableEntity {
		t.Errorf("without an answer: %d", code)
	}
}
