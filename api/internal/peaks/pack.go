// Package peaks builds the pack for recognising mountains in the app's
// camera view (requirement 68): a height grid of Switzerland and about 50 km
// around it, and the named summits, in one gzipped file the app keeps for
// use without reception.
//
// The format (little endian, gzipped as a whole):
//
//	"ALVYOPK1", version uint32
//	west, north, cellLon, cellLat float64; cols, rows uint32
//	rows×cols int16 heights in metres, from the north-west, each row as
//	  differences to the cell before (the first to 0): smaller when gzipped
//	count uint32; per summit lon, lat float32, ele int16, name length uint16,
//	  name (UTF-8)
//
// Cell (r, c) has its centre at west + (c+0.5)·cellLon, north − (r+0.5)·cellLat.
package peaks

import (
	"bufio"
	"compress/gzip"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"io"
	"math"
)

// Version changes when the format or the grid does.
const Version = 1

// The grid: about 150 m cells, from West, North to 11.5°E, 45.2°N.
const (
	West    = 5.0
	North   = 48.4
	CellLon = 0.002
	CellLat = 0.00128
	Cols    = 3250
	Rows    = 2500
)

const (
	zoom           = 9 // Mapterhorn's 512-pixel tiles: about 105 m a pixel here
	tileSize       = 512
	magic          = "ALVYOPK1"
	noHeight int16 = 0
)

// Peak is a named summit.
type Peak struct {
	Name     string
	Ele      int
	Lon, Lat float64
}

// TileFunc returns a terrarium-encoded terrain tile at zoom 9.
type TileFunc func(ctx context.Context, x, y int) (image.Image, error)

// pixel returns the tile and the pixel in it of a point at zoom 9.
func pixel(lon, lat float64) (tx, ty, px, py int) {
	n := float64(int(1) << zoom * tileSize)
	x := (lon + 180) / 360 * n
	s := math.Sin(lat * math.Pi / 180)
	y := (0.5 - math.Log((1+s)/(1-s))/(4*math.Pi)) * n
	return int(x) / tileSize, int(y) / tileSize, int(x) % tileSize, int(y) % tileSize
}

// terrarium decodes a height: (R·256 + G + B/256) − 32768.
func terrarium(img image.Image, px, py int) float64 {
	r, g, b, _ := img.At(img.Bounds().Min.X+px, img.Bounds().Min.Y+py).RGBA()
	return float64(r>>8)*256 + float64(g>>8) + float64(b>>8)/256 - 32768
}

// Write builds the pack from the terrain tiles and the summits. Tiles are
// kept one row of tiles at a time.
func Write(ctx context.Context, w io.Writer, tile TileFunc, peaks []Peak) error {
	zw := gzip.NewWriter(w)
	bw := bufio.NewWriter(zw)
	le := binary.LittleEndian
	head := []any{[]byte(magic), uint32(Version), West, North, CellLon, CellLat, uint32(Cols), uint32(Rows)}
	for _, v := range head {
		if err := binary.Write(bw, le, v); err != nil {
			return err
		}
	}

	tiles := map[[2]int]image.Image{}
	row := make([]int16, Cols)
	for r := range Rows {
		lat := North - (float64(r)+0.5)*CellLat
		prev := noHeight
		for c := range Cols {
			lon := West + (float64(c)+0.5)*CellLon
			tx, ty, px, py := pixel(lon, lat)
			img, ok := tiles[[2]int{tx, ty}]
			if !ok {
				// A new row of tiles: the ones above are done.
				for k := range tiles {
					if k[1] < ty {
						delete(tiles, k)
					}
				}
				var err error
				if img, err = tile(ctx, tx, ty); err != nil {
					return fmt.Errorf("peaks: tile %d/%d/%d: %w", zoom, tx, ty, err)
				}
				tiles[[2]int{tx, ty}] = img
			}
			h := int16(math.Round(max(-500, min(9000, terrarium(img, px, py)))))
			row[c] = h - prev
			prev = h
		}
		if err := binary.Write(bw, le, row); err != nil {
			return err
		}
	}

	if err := binary.Write(bw, le, uint32(len(peaks))); err != nil {
		return err
	}
	for _, p := range peaks {
		name := []byte(p.Name)
		if len(name) > math.MaxUint16 {
			name = name[:math.MaxUint16]
		}
		for _, v := range []any{float32(p.Lon), float32(p.Lat), int16(p.Ele), uint16(len(name)), name} {
			if err := binary.Write(bw, le, v); err != nil {
				return err
			}
		}
	}
	if err := bw.Flush(); err != nil {
		return err
	}
	return zw.Close()
}

// Pack is a read pack, for tests and checks.
type Pack struct {
	Version                       uint32
	West, North, CellLon, CellLat float64
	Cols, Rows                    int
	Heights                       []int16 // row by row from the north-west
	Peaks                         []Peak
}

// Height returns the height of the cell around a point.
func (p *Pack) Height(lon, lat float64) int16 {
	c := int((lon - p.West) / p.CellLon)
	r := int((p.North - lat) / p.CellLat)
	if c < 0 || r < 0 || c >= p.Cols || r >= p.Rows {
		return noHeight
	}
	return p.Heights[r*p.Cols+c]
}

// Read reads a pack.
func Read(r io.Reader) (*Pack, error) {
	zr, err := gzip.NewReader(r)
	if err != nil {
		return nil, err
	}
	br := bufio.NewReader(zr)
	le := binary.LittleEndian
	m := make([]byte, len(magic))
	if _, err := io.ReadFull(br, m); err != nil || string(m) != magic {
		return nil, errors.New("peaks: not a pack")
	}
	var p Pack
	var cols, rows uint32
	for _, v := range []any{&p.Version, &p.West, &p.North, &p.CellLon, &p.CellLat, &cols, &rows} {
		if err := binary.Read(br, le, v); err != nil {
			return nil, err
		}
	}
	p.Cols, p.Rows = int(cols), int(rows)
	p.Heights = make([]int16, p.Cols*p.Rows)
	if err := binary.Read(br, le, p.Heights); err != nil {
		return nil, err
	}
	for r := range p.Rows {
		for c := 1; c < p.Cols; c++ {
			p.Heights[r*p.Cols+c] += p.Heights[r*p.Cols+c-1]
		}
	}
	var n uint32
	if err := binary.Read(br, le, &n); err != nil {
		return nil, err
	}
	for range n {
		var lon, lat float32
		var ele int16
		var size uint16
		for _, v := range []any{&lon, &lat, &ele, &size} {
			if err := binary.Read(br, le, v); err != nil {
				return nil, err
			}
		}
		name := make([]byte, size)
		if _, err := io.ReadFull(br, name); err != nil {
			return nil, err
		}
		p.Peaks = append(p.Peaks, Peak{Name: string(name), Ele: int(ele), Lon: float64(lon), Lat: float64(lat)})
	}
	return &p, nil
}
