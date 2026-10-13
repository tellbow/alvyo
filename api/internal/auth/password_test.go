package auth

import (
	"strings"
	"testing"
	"time"
)

func TestPasswordRoundTrip(t *testing.T) {
	h, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(h, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Errorf("unexpected format %q", h)
	}
	if ok, err := VerifyPassword("correct horse battery", h); !ok || err != nil {
		t.Errorf("valid password rejected: %v", err)
	}
	if ok, _ := VerifyPassword("wrong horse battery", h); ok {
		t.Error("wrong password accepted")
	}
	h2, _ := HashPassword("correct horse battery")
	if h == h2 {
		t.Error("hashes must be salted")
	}
}

func TestVerifyPasswordRejectsGarbage(t *testing.T) {
	for _, h := range []string{"", "plain", "$bcrypt$x$y$z$w", "$argon2id$v=18$m=1,t=1,p=1$AA$AA"} {
		if ok, err := VerifyPassword("x", h); ok || err == nil {
			t.Errorf("%q: ok=%v err=%v", h, ok, err)
		}
	}
}

func TestHashCost(t *testing.T) {
	if testing.Short() || raceEnabled {
		t.Skip()
	}
	start := time.Now()
	_, _ = HashPassword("timing")
	if d := time.Since(start); d > 250*time.Millisecond {
		t.Errorf("hashing took %v; keep logins below 250 ms", d)
	}
}
