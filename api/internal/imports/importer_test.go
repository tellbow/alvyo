package imports

import (
	"context"
	"errors"
	"testing"

	"github.com/tellbow/alvyo/swiss/geo"
)

func TestContentRejectsTracksWithoutLine(t *testing.T) {
	// A Komoot tour without coordinates, a single point, a point twice:
	// too short, not a crash. (No router needed: rejected before.)
	im := &Importer{}
	for _, pts := range [][]geo.Point{nil, {{Lon: 8, Lat: 46.5}}, {{Lon: 8, Lat: 46.5}, {Lon: 8, Lat: 46.5}}} {
		if _, err := im.Content(context.Background(), Track{Name: "Leer", Points: pts}); !errors.Is(err, ErrShort) {
			t.Errorf("%v: err = %v, want ErrShort", pts, err)
		}
	}
}
