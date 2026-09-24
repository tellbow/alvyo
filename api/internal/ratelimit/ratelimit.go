// Package ratelimit limits request rates per key (client IP, e-mail, user).
// State is in memory, which is fine for a single API instance.
package ratelimit

import (
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// Limiter is a set of token buckets, one per key.
type Limiter struct {
	every time.Duration
	burst int

	mu      sync.Mutex
	buckets map[string]*bucket
	calls   int
}

type bucket struct {
	lim  *rate.Limiter
	seen time.Time
}

// New allows burst requests at once and then one request per every.
func New(every time.Duration, burst int) *Limiter {
	return &Limiter{every: every, burst: burst, buckets: map[string]*bucket{}}
}

// Allow reports whether a request for key may proceed now.
func (l *Limiter) Allow(key string) bool { return l.AllowN(key, 1) }

// AllowN is Allow for a request that counts n times, e.g. a file of n
// tracks; at most the burst, so that any request can pass when rested.
func (l *Limiter) AllowN(key string, n int) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	l.calls++
	if l.calls%1000 == 0 {
		l.prune(now)
	}
	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{lim: rate.NewLimiter(rate.Every(l.every), l.burst)}
		l.buckets[key] = b
	}
	b.seen = now
	return b.lim.AllowN(now, min(n, l.burst))
}

// prune drops buckets that have been idle long enough to be full again.
func (l *Limiter) prune(now time.Time) {
	idle := l.every * time.Duration(l.burst)
	for k, b := range l.buckets {
		if now.Sub(b.seen) > idle {
			delete(l.buckets, k)
		}
	}
}
