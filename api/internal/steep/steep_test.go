package steep

import (
	"context"
	"math"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

// eastward is steeper the further east: 20° at 7.000, 40° at 7.004.
type eastward struct{}

func (eastward) Slope(p geo.Point) (float64, error) {
	if p.Lon > 7.0045 {
		return math.NaN(), nil // beyond the data
	}
	return 20 + (p.Lon-7)/0.004*20, nil
}

func TestOf(t *testing.T) {
	line := []geo.Point{{Lon: 7, Lat: 46.5}, {Lon: 7.005, Lat: 46.5}} // about 383 m
	got, err := Of(context.Background(), eastward{}, line)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Known || len(got.Stretches) != 3 {
		t.Fatalf("%+v", got)
	}
	for i, s := range got.Stretches {
		if s.Class != i+1 || (i > 0 && s.FromM != got.Stretches[i-1].ToM) {
			t.Errorf("stretch %d: %+v", i, s)
		}
	}
	// 30° at 7.002, data up to 7.0045: about 2.5/5 of the line.
	if want := 383 * 2.5 / 5; math.Abs(got.SteepM-want) > 15 {
		t.Errorf("steep %v m, want about %v", got.SteepM, want)
	}

	if got, _ := Of(context.Background(), nil, line); got.Known || len(got.Stretches) != 0 {
		t.Errorf("without terrain: %+v", got)
	}
	abroad := []geo.Point{{Lon: 7.01, Lat: 46.5}, {Lon: 7.02, Lat: 46.5}}
	if got, _ := Of(context.Background(), eastward{}, abroad); got.Known {
		t.Errorf("abroad: %+v", got)
	}
}
