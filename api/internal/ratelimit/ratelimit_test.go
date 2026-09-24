package ratelimit

import (
	"testing"
	"time"
)

func TestAllowN(t *testing.T) {
	l := New(time.Hour, 10)
	if !l.AllowN("a", 8) || l.AllowN("a", 3) || !l.Allow("a") || !l.Allow("a") || l.Allow("a") {
		t.Error("10 at once, then no more")
	}
	if !l.AllowN("b", 50) || l.Allow("b") {
		t.Error("more than the burst: all of it, once")
	}
	if !l.Allow("c") {
		t.Error("keys are separate")
	}
}

func TestPrune(t *testing.T) {
	l := New(time.Millisecond, 1)
	l.Allow("old")
	l.prune(time.Now().Add(time.Second))
	if len(l.buckets) != 0 {
		t.Errorf("%d buckets left", len(l.buckets))
	}
}
