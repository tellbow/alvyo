package stageplan

import (
	"errors"
	"reflect"
	"testing"
)

// minutes is a line of h hours with a vertex every minute.
func minutes(h int) []float64 {
	secs := make([]float64, h*60+1)
	for i := range secs {
		secs[i] = float64(i * 60)
	}
	return secs
}

// every puts a preferred place every step minutes (not at the ends).
func every(h, step int) []Candidate {
	var out []Candidate
	for m := step; m < h*60; m += step {
		out = append(out, Candidate{Index: m, Preferred: true})
	}
	return out
}

// hours of the day ends picked.
func hours(cands []Candidate, ends []int) []float64 {
	var out []float64
	for _, e := range ends {
		out = append(out, float64(cands[e].Index)/60)
	}
	return out
}

func TestSplitDays(t *testing.T) {
	cands := every(30, 60)
	ends, err := Split(minutes(30), cands, Days{N: 3})
	if err != nil || !reflect.DeepEqual(hours(cands, ends), []float64{10, 20}) {
		t.Errorf("3 days: %v %v", hours(cands, ends), err)
	}
	// More days than places: one day per place.
	few := []Candidate{{Index: 600, Preferred: true}}
	if ends, _ := Split(minutes(30), few, Days{N: 4}); len(ends) != 1 {
		t.Errorf("4 days, one place: %v", ends)
	}
}

func TestSplitTarget(t *testing.T) {
	// 30 h at 8 h a day: four even days beat 8 + 8 + 8 + 6.
	cands := every(30, 30)
	ends, err := Split(minutes(30), cands, Days{TargetS: 8 * 3600})
	if err != nil || !reflect.DeepEqual(hours(cands, ends), []float64{7.5, 15, 22.5}) {
		t.Errorf("8 h days: %v %v", hours(cands, ends), err)
	}
	// Short enough for one day.
	if ends, _ := Split(minutes(6), every(6, 60), Days{TargetS: 8 * 3600}); len(ends) != 0 {
		t.Errorf("6 h at 8 h a day: %v", ends)
	}
}

func TestSplitPreferences(t *testing.T) {
	line := minutes(20)
	// A preferred place an hour off the middle beats another kind 1 h off…
	cands := []Candidate{{Index: 540}, {Index: 660, Preferred: true}}
	ends, _ := Split(line, cands, Days{N: 2})
	if got := hours(cands, ends); !reflect.DeepEqual(got, []float64{11}) {
		t.Errorf("preferred 1 h off: %v", got)
	}
	// …but not a place of another kind right in the middle when the
	// preferred one is 2 h off.
	cands = []Candidate{{Index: 600}, {Index: 720, Preferred: true}}
	ends, _ = Split(line, cands, Days{N: 2})
	if got := hours(cands, ends); !reflect.DeepEqual(got, []float64{10}) {
		t.Errorf("preferred 2 h off: %v", got)
	}
}

func TestSplitDetour(t *testing.T) {
	// The way to a place and back counts: 10 h + 1.5 h detour makes two
	// days of 11.5 h, worse than 9.5 h and 10.5 h.
	cands := []Candidate{{Index: 570, Preferred: true}, {Index: 600, DetourS: 5400, Preferred: true}}
	ends, _ := Split(minutes(20), cands, Days{N: 2})
	if got := hours(cands, ends); !reflect.DeepEqual(got, []float64{9.5}) {
		t.Errorf("detour: %v", got)
	}
}

func TestSplitMaximum(t *testing.T) {
	// Days over the maximum only when there is no other way.
	cands := []Candidate{{Index: 240, Preferred: true}, {Index: 540, Preferred: true}}
	ends, _ := Split(minutes(16), cands, Days{TargetS: 8 * 3600, MaxS: 9 * 3600})
	if got := hours(cands, ends); !reflect.DeepEqual(got, []float64{9}) {
		t.Errorf("under the maximum: %v", got) // 9 + 7, not 4 + 12
	}
	cands = []Candidate{{Index: 120, Preferred: true}}
	ends, _ = Split(minutes(16), cands, Days{N: 2, MaxS: 9 * 3600})
	if len(ends) != 1 {
		t.Errorf("two days asked for, only over the maximum: %v", ends)
	}
}

func TestSplitNoDays(t *testing.T) {
	if _, err := Split(minutes(5), nil, Days{}); !errors.Is(err, ErrNoDays) {
		t.Errorf("err = %v", err)
	}
}

func TestSplitUnusablePlaces(t *testing.T) {
	// Places at the start and the end (the stations) cannot end a day: with
	// three days asked for, the one place between makes two.
	line := minutes(20)
	cands := []Candidate{{Index: 0, Preferred: true}, {Index: 600, Preferred: true}, {Index: len(line) - 1, Preferred: true}}
	ends, err := Split(line, cands, Days{N: 3})
	if err != nil || !reflect.DeepEqual(ends, []int{1}) {
		t.Errorf("3 days, one usable place: %v %v", ends, err)
	}
	// None usable: one day.
	if ends, err := Split(line, cands[:1], Days{N: 2}); err != nil || len(ends) != 0 {
		t.Errorf("2 days, no usable place: %v %v", ends, err)
	}
}
