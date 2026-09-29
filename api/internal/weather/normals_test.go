package weather

import (
	"math"
	"testing"
)

func TestClimateAt(t *testing.T) {
	// Grindelwald in July and January.
	july, ok := ClimateAt(8.0414, 46.6242, 1034, 7)
	if !ok || july.Station == "" || july.RainStation == "" || july.Month != 7 {
		t.Fatalf("july: %+v %v", july, ok)
	}
	if july.MinC >= july.MaxC || july.MaxC < 15 || july.MaxC > 28 || july.RainDays < 5 || july.RainDays > 20 || july.RainMM < 50 {
		t.Errorf("july: %+v", july)
	}
	jan, _ := ClimateAt(8.0414, 46.6242, 1034, 1)
	if jan.MaxC >= july.MaxC-8 {
		t.Errorf("january %+v not colder than july %+v", jan, july)
	}
	// A thousand metres up, 6.5 °C colder (the same station).
	up, _ := ClimateAt(8.0414, 46.6242, 2034, 7)
	if up.Station == july.Station && math.Abs(july.MaxC-up.MaxC-6.5) > 0.11 {
		t.Errorf("up: %+v", up)
	}
	// Far across the border: none.
	if c, ok := ClimateAt(4.8, 44.5, 500, 7); ok {
		t.Errorf("france: %+v", c)
	}
	if _, ok := ClimateAt(8.0, 46.6, 500, 13); ok {
		t.Error("month 13")
	}
}
