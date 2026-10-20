package snow

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/png"
	"math"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

const (
	// stepM is how densely a line is sampled; a tile's pixel is about 50 m.
	stepM = 10
	// bridgeM joins snow interrupted for less than about a pixel: one
	// stretch, not two.
	bridgeM = 60
	// MinM is how much snow (or patches) a line needs for it to be said:
	// a few patches high up in August are not worth it.
	MinM = 100
	// SteepDeg is the slope from which snow is said to be steep (the BFU's
	// and SAC's 30°).
	SteepDeg = 30
	// minSteepM: less steep terrain in a stretch than a pixel of snow is
	// not said (a rock beside the path).
	minSteepM = 50
	// MaxLineM bounds what is sampled.
	MaxLineM = 500_000
)

// The tiles' colour indices (snow-cover.py): 0 none, then from Legend.
const (
	patches = 1 // 15–50 %
	mostly  = 2 // 50–90 %; from here on it counts as snow
)

// Terrain gives the slope of the terrain in degrees, NaN where unknown.
type Terrain interface {
	Slope(p geo.Point) (float64, error)
}

// Stretch is a part of a line in snow.
type Stretch struct {
	FromM  float64 `json:"from_m" doc:"From the start of the line (of the stage, for a journey)"`
	ToM    float64 `json:"to_m"`
	SteepM float64 `json:"steep_m" doc:"How much of it lies on terrain steeper than 30°"`
	// Line is the stretch itself, [lon, lat]: where the map goes on a tap.
	Line [][2]float64 `json:"line"`
	// Stage is the number (from 1) of a journey's stage.
	Stage int `json:"stage,omitempty"`
}

// Along is the snow on a line.
type Along struct {
	Date      string    `json:"date,omitempty" doc:"The day of the snow cover (YYYY-MM-DD); missing while there is none"`
	SnowM     float64   `json:"snow_m" doc:"In snow (from 50 %), 0 below 100 m"`
	SteepM    float64   `json:"steep_m" doc:"Of that, on terrain steeper than 30°"`
	PatchesM  float64   `json:"patches_m" doc:"Elsewhere in patches (15–50 %), 0 below 100 m"`
	Slopes    bool      `json:"slopes" doc:"Whether the terrain's slope is known (swissALTI3D: Switzerland only)"`
	Stretches []Stretch `json:"stretches"`
	// Attribution is the credit the data policy asks for.
	Attribution string `json:"attribution"`
}

// Along samples the newest day's snow cover along line: where it is snow
// (from 50 %) and how much of that is steep, and the patches elsewhere.
func (s *Store) Along(ctx context.Context, line []geo.Point) (Along, error) {
	terrain := s.Terrain
	out := Along{Stretches: []Stretch{}, Attribution: Attribution, Slopes: terrain != nil}
	day, ok, err := s.Latest(ctx)
	if err != nil || !ok {
		return out, err
	}
	out.Date = day.Format(time.DateOnly)
	if len(line) < 2 {
		return out, nil
	}
	pts, _ := geo.Densify(line, stepM)
	dist := geo.CumulativeDistance(pts)

	// Each piece between two points takes the class of its middle.
	tiles := map[[2]int]*image.Paletted{}
	class := make([]uint8, len(pts)-1)
	for i := range class {
		if err := ctx.Err(); err != nil {
			return out, err
		}
		c, err := s.classAt(ctx, day, tiles, mid(pts[i], pts[i+1]))
		if err != nil {
			return out, err
		}
		class[i] = c
	}

	// Stretches of snow, with short gaps bridged.
	var runs [][2]int // piece indices, end exclusive
	for i := 0; i < len(class); {
		if class[i] < mostly {
			i++
			continue
		}
		j := i
		for j < len(class) && class[j] >= mostly {
			j++
		}
		if n := len(runs); n > 0 && dist[i]-dist[runs[n-1][1]] < bridgeM {
			runs[n-1][1] = j
		} else {
			runs = append(runs, [2]int{i, j})
		}
		i = j
	}
	inSnow := make([]bool, len(class))
	for _, r := range runs {
		st := Stretch{FromM: math.Round(dist[r[0]]), ToM: math.Round(dist[r[1]])}
		for i := r[0]; i < r[1]; i++ {
			inSnow[i] = true
			if terrain == nil {
				continue
			}
			deg, err := terrain.Slope(mid(pts[i], pts[i+1]))
			if err != nil {
				return out, err
			}
			if deg > SteepDeg { // NaN never is
				st.SteepM += dist[i+1] - dist[i]
			}
		}
		st.SteepM = math.Round(st.SteepM)
		if st.SteepM < minSteepM {
			st.SteepM = 0
		}
		for _, p := range geo.Simplify(pts[r[0]:r[1]+1], 5) {
			st.Line = append(st.Line, [2]float64{round5(p.Lon), round5(p.Lat)})
		}
		out.SnowM += st.ToM - st.FromM
		out.SteepM += st.SteepM
		out.Stretches = append(out.Stretches, st)
	}
	for i, c := range class {
		if c == patches && !inSnow[i] {
			out.PatchesM += dist[i+1] - dist[i]
		}
	}
	out.PatchesM = math.Round(out.PatchesM)
	if out.SnowM < MinM {
		out.SnowM, out.SteepM, out.Stretches = 0, 0, []Stretch{}
	}
	if out.PatchesM < MinM {
		out.PatchesM = 0
	}
	return out, nil
}

// classAt is the colour index of the MaxZoom tile's pixel at p: 0 without
// snow (or without a tile there).
func (s *Store) classAt(ctx context.Context, day time.Time, tiles map[[2]int]*image.Paletted, p geo.Point) (uint8, error) {
	n := math.Exp2(MaxZoom)
	x := (p.Lon + 180) / 360 * n
	lat := p.Lat * math.Pi / 180
	y := (1 - math.Log(math.Tan(lat)+1/math.Cos(lat))/math.Pi) / 2 * n
	key := [2]int{int(x), int(y)}
	img, seen := tiles[key]
	if !seen {
		b, err := s.Tile(ctx, day, MaxZoom, key[0], key[1])
		if err != nil {
			return 0, err
		}
		if b != nil {
			decoded, err := png.Decode(bytes.NewReader(b))
			if err != nil {
				return 0, fmt.Errorf("snow: tile %d/%d/%d: %w", MaxZoom, key[0], key[1], err)
			}
			var ok bool
			if img, ok = decoded.(*image.Paletted); !ok {
				return 0, fmt.Errorf("snow: tile %d/%d/%d: not paletted", MaxZoom, key[0], key[1])
			}
		}
		tiles[key] = img
	}
	if img == nil {
		return 0, nil
	}
	b := img.Bounds()
	px := b.Min.X + int((x-float64(key[0]))*float64(b.Dx()))
	py := b.Min.Y + int((y-float64(key[1]))*float64(b.Dy()))
	return img.ColorIndexAt(px, py), nil
}

func mid(a, b geo.Point) geo.Point {
	return geo.Point{Lon: (a.Lon + b.Lon) / 2, Lat: (a.Lat + b.Lat) / 2}
}

// round5 keeps about a metre.
func round5(v float64) float64 { return math.Round(v*1e5) / 1e5 }
