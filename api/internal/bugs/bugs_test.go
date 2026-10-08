package bugs

import (
	"strings"
	"testing"
)

func TestTitle(t *testing.T) {
	if got := Title("  Karte leer\nmehr dazu"); got != "Karte leer" {
		t.Errorf("first line: %q", got)
	}
	if got := Title(strings.Repeat("ä", 100)); len([]rune(got)) != 80 || !strings.HasSuffix(got, "…") {
		t.Errorf("long: %q", got)
	}
}

func TestPlace(t *testing.T) {
	for in, want := range map[string]string{
		"/live/abc123":                     "/live/-",
		"/en/friends/invite/xyz?x=1":       "/en/friends/invite/-?x=1",
		"/routes/42?t=share":               "/routes/42",
		"/reset-password?token=s3cret&a=b": "/reset-password?a=b",
		"/routes\n- [click](https://x.y)":  "/routes - [click](https://x.y)",
		"Route 42":                         "Route 42",
	} {
		if got := Place(in); got != want {
			t.Errorf("Place(%q) = %q, want %q", in, got, want)
		}
	}
}
