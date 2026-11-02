package spam

import (
	"context"
	"errors"
	"net"
	"strconv"
	"testing"
	"time"
)

func answer(t *testing.T, challenge string, bits int) string {
	t.Helper()
	for n := range 1 << 24 {
		if s := strconv.Itoa(n); solved(challenge, s, bits) {
			return s
		}
	}
	t.Fatal("no nonce found")
	return ""
}

func TestCheck(t *testing.T) {
	at := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	g := New()
	g.Bits = 8
	g.now = func() time.Time { return at }
	c := g.Challenge()
	n := answer(t, c, 8)

	if g.Check(c, n) {
		t.Error("answered at once: a person needs a moment")
	}
	at = at.Add(g.Wait)
	if g.Check(c, "x") {
		t.Error("a wrong nonce passed")
	}
	if g.Check(c+"x", n) || New().Check(c, n) {
		t.Error("a challenge that is not ours passed")
	}
	if g.Check("", "") || g.Check("a.b.c.d", "1") {
		t.Error("nonsense passed")
	}
	if !g.Check(c, n) {
		t.Error("a good answer failed")
	}
	if g.Check(c, n) {
		t.Error("the same answer passed twice")
	}

	old := g.Challenge()
	at = at.Add(maxAge + time.Second)
	if g.Check(old, answer(t, old, 8)) {
		t.Error("an expired challenge passed")
	}
}

func TestCheckNeedsTheBitsAsked(t *testing.T) {
	g := New()
	g.Wait = 0
	c := g.Challenge()
	for n := range 1 << 16 {
		// Enough work for one bit, too little for the challenge's.
		if s := strconv.Itoa(n); solved(c, s, 1) && !solved(c, s, g.Bits) {
			if g.Check(c, s) {
				t.Error("too little work passed")
			}
			return
		}
	}
	t.Fatal("no such nonce")
}

func TestPrune(t *testing.T) {
	at := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	g := Relaxed()
	g.now = func() time.Time { return at }
	c := g.Challenge()
	if !g.Check(c, answer(t, c, 1)) {
		t.Fatal("a good answer failed")
	}
	at = at.Add(maxAge + 2*time.Minute)
	c = g.Challenge()
	if !g.Check(c, answer(t, c, 1)) || len(g.used) != 1 {
		t.Errorf("%d used challenges kept", len(g.used))
	}
}

func TestOff(t *testing.T) {
	if !Off().Check("", "") || !Off().MailboxOK(context.Background(), "a@mailinator.com") {
		t.Error("off lets everything through")
	}
}

type fakeDNS struct {
	mx      []*net.MX
	mxErr   error
	hostErr error
}

func (f fakeDNS) LookupMX(context.Context, string) ([]*net.MX, error) { return f.mx, f.mxErr }
func (f fakeDNS) LookupHost(context.Context, string) ([]string, error) {
	return []string{"192.0.2.1"}, f.hostErr
}

func TestPlausible(t *testing.T) {
	missing := &net.DNSError{Err: "no such host", IsNotFound: true}
	broken := &net.DNSError{Err: "server misbehaving", IsTemporary: true}
	mail := []*net.MX{{Host: "mail.example.ch.", Pref: 10}}
	for _, c := range []struct {
		name, email string
		dns         fakeDNS
		want        bool
	}{
		{"mail server", "a@example.ch", fakeDNS{mx: mail}, true},
		{"upper case throwaway", "a@MAILINATOR.com", fakeDNS{mx: mail}, false},
		{"null MX", "a@example.com", fakeDNS{mx: []*net.MX{{Host: "."}}}, false},
		{"no MX, an address", "a@example.ch", fakeDNS{mxErr: missing}, true},
		{"no domain at all", "a@nix.invalid", fakeDNS{mxErr: missing, hostErr: missing}, false},
		{"DNS trouble on MX", "a@example.ch", fakeDNS{mxErr: broken, hostErr: missing}, true},
		{"DNS trouble on address", "a@example.ch", fakeDNS{mxErr: missing, hostErr: broken}, true},
		{"timeout", "a@example.ch", fakeDNS{mxErr: errors.Join(context.DeadlineExceeded, broken)}, true},
		{"no at sign", "nobody", fakeDNS{mx: mail}, false},
	} {
		if got := plausible(context.Background(), c.dns, c.email); got != c.want {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
}
