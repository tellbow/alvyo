package tags

import (
	"errors"
	"reflect"
	"strings"
	"testing"
)

func TestNormalize(t *testing.T) {
	got, err := Normalize([]string{"  Winter ", "mit   Kindern", "winter", "", " ", "Tessin"})
	if err != nil || !reflect.DeepEqual(got, []string{"Winter", "mit Kindern", "Tessin"}) {
		t.Errorf("got %q, %v", got, err)
	}
	if got, err := Normalize(nil); err != nil || got == nil || len(got) != 0 {
		t.Errorf("no tags: %#v, %v", got, err)
	}
	if _, err := Normalize([]string{strings.Repeat("ä", MaxLen)}); err != nil {
		t.Errorf("%d characters: %v", MaxLen, err)
	}
	if _, err := Normalize([]string{strings.Repeat("ä", MaxLen+1)}); !errors.Is(err, ErrInvalid) {
		t.Errorf("too long: %v", err)
	}
	many := make([]string, Max+1)
	for i := range many {
		many[i] = strings.Repeat("x", i+1)
	}
	if _, err := Normalize(many); !errors.Is(err, ErrInvalid) {
		t.Errorf("too many: %v", err)
	}
	// Repeats do not count against the limit.
	if _, err := Normalize(append(many[:Max], "X")); err != nil {
		t.Errorf("%d tags and a repeat: %v", Max, err)
	}
}
