package snow

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
	"math"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

// The MaxZoom tile the tests draw on, near Grindelwald, and a row through
// its middle.
const tileX, tileY = 1069, 724

func pixelLon(col float64) float64 { return (float64(tileX)+col/256)/math.Exp2(MaxZoom)*360 - 180 }

func rowLat(row float64) float64 {
	y := (float64(tileY) + row/256) / math.Exp2(MaxZoom)
	return math.Atan(math.Sinh(math.Pi*(1-2*y))) * 180 / math.Pi
}

// eastAt is a line along row 128 from column a to column b.
func eastAt(a, b float64) []geo.Point {
	return []geo.Point{{Lon: pixelLon(a), Lat: rowLat(128)}, {Lon: pixelLon(b), Lat: rowLat(128)}}
}

// steepBetween is terrain of 45° between two columns, 10° elsewhere.
type steepBetween [2]float64

func (s steepBetween) Slope(p geo.Point) (float64, error) {
	if p.Lon >= pixelLon(s[0]) && p.Lon < pixelLon(s[1]) {
		return 45, nil
	}
	return 10, nil
}

// snowTile is a tile as snow-cover.py makes it, with classes by column.
func snowTile(t *testing.T, cols map[[2]int]uint8) []byte {
	t.Helper()
	pal := color.Palette{color.Transparent, color.Gray{200}, color.Gray{150}, color.Gray{100}}
	img := image.NewPaletted(image.Rect(0, 0, 256, 256), pal)
	for r, c := range cols {
		for x := r[0]; x < r[1]; x++ {
			for y := range 256 {
				img.SetColorIndex(x, y, c)
			}
		}
	}
	var b bytes.Buffer
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func TestAlong(t *testing.T) {
	ctx := context.Background()
	s := &Store{DB: testdb.New(t)}
	line := eastAt(20, 240)

	// No snow cover yet: nothing, no day.
	got, err := s.Along(ctx, line)
	if err != nil || got.Date != "" || got.SnowM != 0 || got.Attribution == "" {
		t.Fatalf("without a day: %+v, %v", got, err)
	}

	tile := snowTile(t, map[[2]int]uint8{
		{50, 80}:   3, // a pixel without snow at 80 is bridged
		{81, 91}:   2,
		{150, 152}: 3, // a stretch of its own
		{200, 220}: 1, // patches
	})
	if _, err := s.DB.Exec(ctx, `INSERT INTO snow_days (day) VALUES ('2026-10-18')`); err != nil {
		t.Fatal(err)
	}
	if _, err := s.DB.Exec(ctx, `INSERT INTO snow_tiles (day, z, x, y, png) VALUES ('2026-10-18', $1, $2, $3, $4)`,
		MaxZoom, tileX, tileY, tile); err != nil {
		t.Fatal(err)
	}
	s.Terrain = steepBetween{60, 70}
	got, err = s.Along(ctx, line)
	if err != nil {
		t.Fatal(err)
	}
	px := geo.Distance(geo.Point{Lon: pixelLon(0), Lat: rowLat(128)}, geo.Point{Lon: pixelLon(1), Lat: rowLat(128)})
	near := func(name string, v, want float64) {
		t.Helper()
		if math.Abs(v-want) > 2*stepM {
			t.Errorf("%s: %.0f m, want %.0f m", name, v, want)
		}
	}
	if got.Date != "2026-10-18" || !got.Slopes || len(got.Stretches) != 2 {
		t.Fatalf("along: %+v", got)
	}
	first := got.Stretches[0]
	near("first from", first.FromM, 30*px)
	near("first to", first.ToM, 71*px)
	near("steep", first.SteepM, 10*px)
	near("snow", got.SnowM, 43*px)
	near("patches", got.PatchesM, 20*px)
	if a, b := first.Line[0], first.Line[len(first.Line)-1]; math.Abs(a[0]-pixelLon(50)) > 0.0002 || math.Abs(b[0]-pixelLon(91)) > 0.0002 {
		t.Errorf("first's line %v … %v", a, b)
	}
	if got.Stretches[1].SteepM != 0 {
		t.Errorf("second %+v", got.Stretches[1])
	}

	// A few metres of steep terrain are not said.
	s.Terrain = steepBetween{60, 60.5}
	if got, err := s.Along(ctx, line); err != nil || got.SteepM != 0 || got.Stretches[0].SteepM != 0 {
		t.Errorf("a little steep: %+v, %v", got, err)
	}

	// Without terrain the slope is not known.
	s.Terrain = nil
	if got, err := s.Along(ctx, line); err != nil || got.Slopes || got.SteepM != 0 || got.SnowM == 0 {
		t.Errorf("without terrain: %+v, %v", got, err)
	}
	// Under 100 m of snow (two pixels, one of them half) is not said.
	if got, err := s.Along(ctx, eastAt(150.5, 160)); err != nil || got.SnowM != 0 || len(got.Stretches) != 0 {
		t.Errorf("a little snow: %+v, %v", got, err)
	}
	// Beyond the tiles there is none.
	if got, err := s.Along(ctx, []geo.Point{{Lon: 9.5, Lat: 46.5}, {Lon: 9.51, Lat: 46.5}}); err != nil || got.SnowM != 0 {
		t.Errorf("elsewhere: %+v, %v", got, err)
	}
}
