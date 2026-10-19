package elevation

import (
	"context"
	"errors"
	"fmt"
	"image"
	"image/png"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"sync"

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/lv95"
)

// tilePixels is the side of a swissALTI3D tile: 1 km at 2 m.
const tilePixels = 500

// maxTiles bounds the decoded tiles kept in memory (500 KB each): a leg
// needs 10-30, decoding one again takes about 4 ms.
const maxTiles = 64

// SwissALTI3D samples heights from swisstopo's swissALTI3D kept on disk, as
// infra/data-import/swissalti3d.py writes it: one 16-bit grey PNG per km²
// named E-N (its south-west corner in km of LV95), decimetres, 0 = no data.
// Heights are interpolated bilinearly between the pixels' centres. A line
// with a point without data (beyond the border) is ErrNoCoverage as a whole:
// bridging it would flatten the hills abroad.
type SwissALTI3D struct {
	Dir string

	mu    sync.Mutex
	tiles map[[2]int][]byte // big-endian decimetres; nil: no tile there
}

// Sample implements Sampler.
func (s *SwissALTI3D) Sample(ctx context.Context, pts []geo.Point) ([]float64, error) {
	if len(pts) == 0 {
		return nil, nil
	}
	out := make([]float64, len(pts))
	for i, p := range pts {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		h, err := s.height(lv95.FromWGS84(p.Lon, p.Lat))
		if err != nil {
			return nil, err
		}
		if math.IsNaN(h) {
			return nil, ErrNoCoverage
		}
		out[i] = h
	}
	return out, nil
}

// height at an LV95 point, NaN without data.
func (s *SwissALTI3D) height(e, n float64) (float64, error) {
	// Pixel i (counted from E 0 eastwards, N 0 northwards) has its centre
	// at 2i + 1 m.
	fx, fy := (e-1)/2, (n-1)/2
	x, y := math.Floor(fx), math.Floor(fy)
	tx, ty := fx-x, fy-y
	var v [4]float64
	for k, d := range [4][2]int{{0, 0}, {1, 0}, {0, 1}, {1, 1}} {
		h, err := s.pixel(int(x)+d[0], int(y)+d[1])
		if err != nil {
			return 0, err
		}
		v[k] = h
	}
	if math.IsNaN(v[0] + v[1] + v[2] + v[3]) {
		// At the edge of the data: the nearest pixel, if it has one.
		return v[int(math.Round(tx))+2*int(math.Round(ty))], nil
	}
	return (v[0]*(1-tx)+v[1]*tx)*(1-ty) + (v[2]*(1-tx)+v[3]*tx)*ty, nil
}

// pixel is the height of pixel (x, y), NaN without data.
func (s *SwissALTI3D) pixel(x, y int) (float64, error) {
	key := [2]int{x / tilePixels, y / tilePixels}
	t, err := s.tile(key)
	if err != nil || t == nil {
		return math.NaN(), err
	}
	row := tilePixels - 1 - y%tilePixels // rows run from the north
	i := 2 * (row*tilePixels + x%tilePixels)
	dm := uint16(t[i])<<8 | uint16(t[i+1])
	if dm == 0 {
		return math.NaN(), nil
	}
	return float64(dm) / 10, nil
}

func (s *SwissALTI3D) tile(key [2]int) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if t, ok := s.tiles[key]; ok {
		return t, nil
	}
	t, err := readTile(filepath.Join(s.Dir, fmt.Sprintf("%d-%d.png", key[0], key[1])))
	if err != nil {
		return nil, err
	}
	if s.tiles == nil {
		s.tiles = map[[2]int][]byte{}
	}
	if len(s.tiles) >= maxTiles {
		for k := range s.tiles { // any one; a route rarely comes back to a tile
			delete(s.tiles, k)
			break
		}
	}
	s.tiles[key] = t
	return t, nil
}

func readTile(path string) ([]byte, error) {
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("elevation: %w", err)
	}
	defer func() { _ = f.Close() }()
	img, err := png.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("elevation: %s: %w", path, err)
	}
	g, ok := img.(*image.Gray16)
	if !ok || g.Rect.Dx() != tilePixels || g.Rect.Dy() != tilePixels {
		return nil, fmt.Errorf("elevation: %s: not a %d×%d 16-bit grey image", path, tilePixels, tilePixels)
	}
	return g.Pix, nil // Stride is 2 × 500 for a whole image
}
