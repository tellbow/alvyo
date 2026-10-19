package elevation

import (
	"context"
	"errors"
	"log/slog"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Fallback samples with First and, where it has no data for the whole line
// or fails, with Second: our own swissALTI3D, then geo.admin for lines
// beyond the border (and before the tiles are there).
type Fallback struct {
	First, Second Sampler
}

// Sample implements Sampler.
func (f Fallback) Sample(ctx context.Context, pts []geo.Point) ([]float64, error) {
	h, err := f.First.Sample(ctx, pts)
	if err == nil || ctx.Err() != nil {
		return h, err
	}
	if !errors.Is(err, ErrNoCoverage) {
		// A broken tile: still a line, and in the logs.
		slog.WarnContext(ctx, "elevation: falling back", "err", err)
	}
	return f.Second.Sample(ctx, pts)
}
