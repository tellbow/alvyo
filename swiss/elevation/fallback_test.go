package elevation

import (
	"context"
	"errors"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

type fakeSampler struct {
	h     []float64
	err   error
	calls int
}

func (f *fakeSampler) Sample(context.Context, []geo.Point) ([]float64, error) {
	f.calls++
	return f.h, f.err
}

func TestFallback(t *testing.T) {
	ours := []float64{1}
	theirs := []float64{2}
	for _, tc := range []struct {
		name   string
		err    error
		want   []float64
		second int
	}{
		{"our tiles cover the line", nil, ours, 0},
		{"beyond the border", ErrNoCoverage, theirs, 1},
		{"a broken tile", errors.New("elevation: x.png: unexpected EOF"), theirs, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			first := &fakeSampler{h: ours, err: tc.err}
			second := &fakeSampler{h: theirs}
			h, err := Fallback{First: first, Second: second}.Sample(context.Background(), line(2))
			if err != nil || h[0] != tc.want[0] || second.calls != tc.second {
				t.Errorf("h %v err %v, second asked %d times; want %v, %d", h, err, second.calls, tc.want, tc.second)
			}
		})
	}
}

func TestFallbackCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	second := &fakeSampler{}
	_, err := Fallback{First: &fakeSampler{err: context.Canceled}, Second: second}.Sample(ctx, line(2))
	if !errors.Is(err, context.Canceled) || second.calls != 0 {
		t.Errorf("err %v, second asked %d times", err, second.calls)
	}
}
