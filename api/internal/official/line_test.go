package official

import (
	"slices"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

func pt(lon, lat float64) geo.Point { return geo.Point{Lon: lon, Lat: lat} }

func TestLineJoinsPiecesInEitherDirection(t *testing.T) {
	a, b, c, d := pt(8.0, 46.0), pt(8.01, 46.0), pt(8.02, 46.0), pt(8.03, 46.0)
	got := Line([][]geo.Point{{c, b}, {a, b}, {c, d}}) // shuffled, two turned round
	if want := []geo.Point{a, b, c, d}; !slices.Equal(got, want) && !slices.Equal(got, []geo.Point{d, c, b, a}) {
		t.Fatalf("line %v, want %v or its reverse", got, want)
	}
}

func TestLineDropsLoopsAndSideBranches(t *testing.T) {
	a, b, c, d := pt(8.0, 46.0), pt(8.01, 46.0), pt(8.02, 46.0), pt(8.03, 46.0)
	loop := []geo.Point{b, pt(8.01, 46.001), pt(8.011, 46.001), b} // round a station
	branch := []geo.Point{c, pt(8.02, 46.002)}                     // 220 m to a viewpoint
	got := Line([][]geo.Point{{a, b}, loop, {b, c}, branch, {c, d}})
	if want := []geo.Point{a, b, c, d}; !slices.Equal(got, want) && !slices.Equal(got, []geo.Point{d, c, b, a}) {
		t.Fatalf("line %v, want %v or its reverse", got, want)
	}
}

func TestLineChainsPiecesWithGaps(t *testing.T) {
	a, b, c, d := pt(8.0, 46.0), pt(8.01, 46.0), pt(8.0101, 46.0), pt(8.03, 46.0)
	got := Line([][]geo.Point{{c, d}, {b, a}}) // 8 m apart
	if want := []geo.Point{a, b, c, d}; !slices.Equal(got, want) && !slices.Equal(got, []geo.Point{d, c, b, a}) {
		t.Fatalf("line %v, want %v or its reverse", got, want)
	}
}

func TestLineOfALoopRoute(t *testing.T) {
	ring := []geo.Point{pt(8, 46), pt(8.01, 46), pt(8.01, 46.01), pt(8, 46)}
	if got := Line([][]geo.Point{ring}); !slices.Equal(got, ring) {
		t.Fatalf("line %v, want the ring", got)
	}
	if got := Line(nil); got != nil {
		t.Fatalf("no pieces: %v", got)
	}
}

func TestOrientMakesStagesFollowOneAnother(t *testing.T) {
	a, b, c, d := pt(8.0, 46.0), pt(8.01, 46.0), pt(8.02, 46.0), pt(8.03, 46.0)
	lines := [][]geo.Point{{b, a}, {b, c}, {d, c}}
	Orient(lines)
	if want := [][]geo.Point{{a, b}, {b, c}, {c, d}}; !slices.EqualFunc(lines, want, slices.Equal) {
		t.Fatalf("oriented %v, want %v", lines, want)
	}
}

func TestLineWalksACircuitInPieces(t *testing.T) {
	// A circuit in three pieces, with a branch of 150 m to a stop: all of the
	// circuit, not the short way between two ends.
	a, b, c := pt(8.0, 46.0), pt(8.02, 46.0), pt(8.01, 46.01)
	stop := pt(8.0, 45.9987)
	got := Line([][]geo.Point{{a, b}, {c, b}, {c, a}, {a, stop}})
	want := length([]geo.Point{a, b, c, a})
	if m := length(got); m < want-1 || m > want+1 {
		t.Fatalf("line of %.0f m, want %.0f: %v", m, want, got)
	}
	if got[0] != got[len(got)-1] {
		t.Errorf("a circuit that does not come back: %v", got)
	}
}

func TestLineWalksALoopOnTheWay(t *testing.T) {
	// From a to b, round a loop b–c–d–b, back to b and on to e.
	a, b, c, d, e := pt(8.0, 46.0), pt(8.01, 46.0), pt(8.02, 46.01), pt(8.02, 45.99), pt(8.0, 46.02)
	got := Line([][]geo.Point{{a, b}, {b, c}, {c, d}, {d, b}, {b, e}})
	want := length([]geo.Point{a, b}) + length([]geo.Point{b, c, d, b}) + length([]geo.Point{b, e})
	if m := length(got); m < want-1 || m > want+1 {
		t.Fatalf("line of %.0f m, want %.0f: %v", m, want, got)
	}
}
