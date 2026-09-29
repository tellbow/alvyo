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
