// Package elevation samples terrain heights along a line.
package elevation

import (
	"context"
	"errors"

	"github.com/tellbow/odysgeh/swiss/geo"
)

// ErrNoCoverage means the elevation source has no data for (part of) the line.
var ErrNoCoverage = errors.New("elevation: no coverage")

// Sampler returns one terrain height in metres for each point.
type Sampler interface {
	Sample(ctx context.Context, pts []geo.Point) ([]float64, error)
}
