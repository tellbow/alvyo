// Package spam keeps bots out of the open forms without a captcha: a signed
// challenge, which is a small proof-of-work and a minimum time to fill the
// form in one, and a check that an e-mail address can receive mail.
package spam

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

const maxAge = 30 * time.Minute

// Guard issues and checks challenges.
type Guard struct {
	Bits    int                                // leading zero bits of the proof-of-work
	Wait    time.Duration                      // the least time from challenge to answer
	Mailbox func(context.Context, string) bool // nil: every address passes
	off     bool
	now     func() time.Time

	// shortcut: the key dies with the process, so a form open during a deploy
	// fails once and works when sent again; a shared key if the API ever runs
	// as several pods.
	key    []byte
	mu     sync.Mutex
	used   map[string]time.Time
	pruned time.Time
}

// New is the guard of production. 16 bits are about 65 000 hashes: under a
// second on a slow phone, and a bot without a browser has to do them at all.
func New() *Guard {
	return &Guard{
		Bits: 16, Wait: 3 * time.Second, Mailbox: MailboxPlausible, now: time.Now,
		key: []byte(rand.Text()), used: map[string]time.Time{},
	}
}

// Relaxed is for end-to-end tests: the whole way, but quick, and for addresses
// without a mailbox. Never in production.
func Relaxed() *Guard {
	g := New()
	g.Bits, g.Wait, g.Mailbox = 1, 0, nil
	return g
}

// Off lets everything through, for tests of something else.
func Off() *Guard {
	g := Relaxed()
	g.off = true
	return g
}

func (g *Guard) sign(payload string) string {
	h := hmac.New(sha256.New, g.key)
	h.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}

// Challenge returns a new challenge: salt, time and bits, signed.
func (g *Guard) Challenge() string {
	p := rand.Text() + "." + strconv.FormatInt(g.now().UnixMilli(), 10) + "." + strconv.Itoa(g.Bits)
	return p + "." + g.sign(p)
}

// Check says whether the nonce answers a challenge of ours, not used before,
// neither too quick nor too old. A good answer counts only once.
func (g *Guard) Check(challenge, nonce string) bool {
	if g.off {
		return true
	}
	parts := strings.Split(challenge, ".")
	if len(parts) != 4 || !hmac.Equal([]byte(parts[3]), []byte(g.sign(strings.Join(parts[:3], ".")))) {
		return false
	}
	issued, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return false
	}
	bits, err := strconv.Atoi(parts[2])
	if err != nil {
		return false
	}
	now := g.now()
	age := now.Sub(time.UnixMilli(issued))
	if age < g.Wait || age > maxAge || !solved(challenge, nonce, bits) {
		return false
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	if _, again := g.used[parts[0]]; again {
		return false
	}
	if now.Sub(g.pruned) > time.Minute {
		g.pruned = now
		for salt, at := range g.used {
			if now.Sub(at) > maxAge {
				delete(g.used, salt)
			}
		}
	}
	g.used[parts[0]] = now
	return true
}

// solved: SHA-256 of "challenge:nonce" starts with that many zero bits.
func solved(challenge, nonce string, bits int) bool {
	sum := sha256.Sum256([]byte(challenge + ":" + nonce))
	if bits > len(sum)*8 {
		return false
	}
	for i := range bits {
		if sum[i>>3]&(0x80>>(i&7)) != 0 {
			return false
		}
	}
	return true
}

// MailboxOK says whether the address may sign up.
func (g *Guard) MailboxOK(ctx context.Context, email string) bool {
	return g.off || g.Mailbox == nil || g.Mailbox(ctx, email)
}

// shortcut: the most common throwaway domains only; add one when it slips through.
var disposable = map[string]bool{
	"10minutemail.com": true, "burnermail.io": true, "dispostable.com": true, "emailondeck.com": true,
	"fakeinbox.com": true, "getnada.com": true, "guerrillamail.com": true, "guerrillamail.net": true,
	"mailinator.com": true, "maildrop.cc": true, "mailnesia.com": true, "mintemail.com": true,
	"moakt.com": true, "mohmal.com": true, "sharklasers.com": true, "spamgourmet.com": true,
	"tempail.com": true, "temp-mail.org": true, "tempmail.com": true, "throwawaymail.com": true,
	"trashmail.com": true, "yopmail.com": true,
}

type resolver interface {
	LookupMX(ctx context.Context, name string) ([]*net.MX, error)
	LookupHost(ctx context.Context, name string) ([]string, error)
}

// MailboxPlausible is false for throwaway domains and for domains that cannot
// receive mail.
func MailboxPlausible(ctx context.Context, email string) bool {
	return plausible(ctx, net.DefaultResolver, email)
}

// plausible lets the address through on trouble with DNS: our outage must not
// stop anyone from signing up.
func plausible(ctx context.Context, r resolver, email string) bool {
	_, domain, _ := strings.Cut(strings.ToLower(email), "@")
	if domain == "" || disposable[domain] {
		return false
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	mx, err := r.LookupMX(ctx, domain)
	for _, m := range mx {
		if m.Host != "." {
			return true
		}
	}
	if len(mx) > 0 { // a "null MX": the domain says it takes no mail
		return false
	}
	if err != nil && !notFound(err) {
		return true
	}
	// Without an MX record, mail goes to the domain's own address.
	_, err = r.LookupHost(ctx, domain)
	return err == nil || !notFound(err)
}

func notFound(err error) bool {
	var d *net.DNSError
	return errors.As(err, &d) && d.IsNotFound
}
