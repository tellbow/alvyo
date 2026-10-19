package ratelimit

import (
	"math/rand/v2"
	"sync"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"
)

// TestAllowNModel runs thousands of requests over hours of fake time,
// enough for the limiter to prune its buckets several times, and compares
// every answer with a token bucket kept here.
func TestAllowNModel(t *testing.T) {
	for seed := range uint64(20) {
		synctest.Test(t, func(t *testing.T) {
			rng := rand.New(rand.NewPCG(seed, 1))
			every, burst := time.Minute, 1+rng.IntN(10)
			l := New(every, burst)
			type bucket struct {
				tokens float64
				at     time.Time
			}
			model := map[string]*bucket{}
			keys := []string{"a", "b", "c", "d"}
			for i := range 3000 {
				// Mostly bursts, now and then a long rest.
				pause := time.Duration(rng.IntN(20)) * time.Second
				if rng.IntN(50) == 0 {
					pause = time.Duration(rng.IntN(180)) * time.Minute
				}
				time.Sleep(pause)
				key, n := keys[rng.IntN(len(keys))], 1+rng.IntN(burst+2)

				now := time.Now()
				b := model[key]
				if b == nil {
					b = &bucket{tokens: float64(burst), at: now}
					model[key] = b
				}
				b.tokens = min(float64(burst), b.tokens+now.Sub(b.at).Seconds()/every.Seconds())
				b.at = now
				need := float64(min(n, burst))
				got := l.AllowN(key, n)
				// Leave out the answers that floating point could tip.
				if d := b.tokens - need; d > -1e-6 && d < 1e-6 {
					if got {
						b.tokens -= need
					}
					continue
				}
				if want := b.tokens >= need; got != want {
					t.Fatalf("seed %d, request %d (%s ×%d): %v, want %v with %.3f tokens", seed, i, key, n, got, want, b.tokens)
				}
				if got {
					b.tokens -= need
				}
			}
		})
	}
}

// TestAllowAtOnce: requests arriving at the same moment from many
// goroutines get exactly the burst, however they interleave.
func TestAllowAtOnce(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		l := New(time.Hour, 5)
		var allowed atomic.Int32
		var wg sync.WaitGroup
		for range 50 {
			wg.Go(func() {
				if l.Allow("same") {
					allowed.Add(1)
				}
			})
		}
		wg.Wait()
		if allowed.Load() != 5 {
			t.Errorf("%d allowed, want 5", allowed.Load())
		}
		time.Sleep(time.Hour)
		if !l.Allow("same") || l.Allow("same") {
			t.Error("an hour later: one more, not two")
		}
	})
}
