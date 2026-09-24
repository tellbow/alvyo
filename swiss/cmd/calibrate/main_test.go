package main

import "testing"

func TestHM(t *testing.T) {
	for m, want := range map[float64]string{0: "0 h 00", 59.4: "0 h 59", 59.6: "1 h 00", 119.6: "2 h 00", 448: "7 h 28"} {
		if got := hm(m); got != want {
			t.Errorf("hm(%v) = %q, want %q", m, got, want)
		}
	}
}
