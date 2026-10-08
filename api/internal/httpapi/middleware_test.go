package httpapi

import (
	"context"
	"testing"
)

func TestLimitKey(t *testing.T) {
	for ip, want := range map[string]string{
		"203.0.113.7":              "203.0.113.7",
		"2001:db8:1:2:aaaa::1":     "2001:db8:1:2::/64",
		"2001:db8:1:2:bbbb:cc::99": "2001:db8:1:2::/64",
		"::ffff:203.0.113.7":       "::ffff:203.0.113.7",
	} {
		if got := limitKey(context.WithValue(context.Background(), ipKey, ip)); got != want {
			t.Errorf("limitKey(%s) = %s, want %s", ip, got, want)
		}
	}
}
