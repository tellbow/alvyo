// Package packs builds offline map packs: the swisstopo national map and
// hiking trail tiles within a corridor around routes, as PMTiles archives
// that the app downloads in one piece and reads without network.
package packs

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"

	"github.com/tellbow/odysgeh/swiss/geo"
)

// What a pack holds.
const (
	MinZoom = 10
	MaxZoom = 16
	// BufferM is the corridor half-width around the route.
	BufferM = 1000
	// MaxTiles bounds one pack (about 400 km of route).
	MaxTiles = 60000
)

// Layer is a map layer in a pack, fetched from the odysgeh tile cache.
type Layer struct {
	ID   string // file name part, e.g. "landeskarte"
	WMTS string // swisstopo layer
	Ext  string
	Type uint8
}

// Layers of every pack.
var Layers = []Layer{
	{"landeskarte", "ch.swisstopo.pixelkarte-farbe", "jpeg", tileJPEG},
	{"wanderwege", "ch.swisstopo.swisstlm3d-wanderwege", "png", tilePNG},
}

// Tile is an XYZ map tile.
type Tile struct {
	Z    uint8
	X, Y uint32
}

// Corridor returns the tiles at MinZoom..MaxZoom within bufferM of lines.
func Corridor(lines [][]geo.Point, bufferM float64) []Tile {
	seen := map[Tile]bool{}
	var out []Tile
	for z := MinZoom; z <= MaxZoom; z++ {
		n := math.Exp2(float64(z))
		for _, line := range lines {
			for i, p := range line {
				// Sample the line densely enough not to skip a tile.
				pts := []geo.Point{p}
				if i > 0 {
					pts = interpolate(line[i-1], p, 40075016.686*math.Cos(p.Lat*math.Pi/180)/n/2)
				}
				for _, q := range pts {
					tileM := 40075016.686 * math.Cos(q.Lat*math.Pi/180) / n
					r := int(math.Ceil(bufferM / tileM))
					fx, fy := lonLatToTile(q, n)
					cx, cy := int(fx), int(fy)
					for dx := -r; dx <= r; dx++ {
						for dy := -r; dy <= r; dy++ {
							// Only tiles whose nearest edge is within the buffer of the point.
							ex := edge(fx, cx+dx) * tileM
							ey := edge(fy, cy+dy) * tileM
							if math.Hypot(ex, ey) > bufferM {
								continue
							}
							t := Tile{uint8(z), uint32(cx + dx), uint32(cy + dy)}
							if !seen[t] {
								seen[t] = true
								out = append(out, t)
							}
						}
					}
				}
			}
		}
	}
	return out
}

// lonLatToTile returns the fractional tile coordinates of p.
func lonLatToTile(p geo.Point, n float64) (float64, float64) {
	lat := p.Lat * math.Pi / 180
	x := (p.Lon + 180) / 360 * n
	y := (1 - math.Log(math.Tan(lat)+1/math.Cos(lat))/math.Pi) / 2 * n
	return x, y
}

// edge is the distance in tiles from coordinate f to tile column/row i.
func edge(f float64, i int) float64 {
	switch {
	case f < float64(i):
		return float64(i) - f
	case f > float64(i+1):
		return f - float64(i+1)
	}
	return 0
}

// interpolate returns points from a (exclusive) to b (inclusive) at most
// step metres apart.
func interpolate(a, b geo.Point, step float64) []geo.Point {
	steps := int(math.Ceil(geo.Distance(a, b) / step))
	if steps < 1 {
		steps = 1
	}
	out := make([]geo.Point, steps)
	for i := 1; i <= steps; i++ {
		f := float64(i) / float64(steps)
		out[i-1] = geo.Point{Lon: a.Lon + (b.Lon-a.Lon)*f, Lat: a.Lat + (b.Lat-a.Lat)*f}
	}
	return out
}

// File is one layer of a built pack.
type File struct {
	Layer string `json:"layer"`
	Name  string `json:"name"`
	Bytes int64  `json:"bytes"`
	Tiles int    `json:"tiles"`
}

// Builder fetches tiles from the tile cache and writes packs into Dir.
type Builder struct {
	TilesURL string // e.g. http://tilecache:8080
	Dir      string
	Client   *http.Client
	Parallel int // concurrent tile requests, default 16
	// Rate paces tile requests of all builds, to stay below the tile
	// cache's limit per address; nil: no pacing.
	Rate *rate.Limiter
}

// ErrTooLarge means a pack would exceed MaxTiles.
var ErrTooLarge = errors.New("packs: the route is too long for one pack")

// Key identifies the pack of a route or journey by what it covers: it
// changes with the line, not with the title.
func Key(kind, id string, lines [][]geo.Point) string {
	h := sha256.New()
	_, _ = fmt.Fprintf(h, "z%d-%d b%d\n", MinZoom, MaxZoom, BufferM)
	for _, l := range lines {
		for _, p := range l {
			_ = binary.Write(h, binary.LittleEndian, [2]float64{p.Lon, p.Lat})
		}
		_, _ = h.Write([]byte{'|'})
	}
	return fmt.Sprintf("%s-%s-%x", kind, id, h.Sum(nil)[:6])
}

// Existing returns the files of a pack built before, if complete.
func (b *Builder) Existing(key string) ([]File, bool) {
	var files []File
	for _, l := range Layers {
		name := key + "-" + l.ID + ".pmtiles"
		st, err := os.Stat(filepath.Join(b.Dir, name))
		if err != nil {
			return nil, false
		}
		files = append(files, File{Layer: l.ID, Name: name, Bytes: st.Size()})
	}
	meta, err := os.ReadFile(filepath.Join(b.Dir, key+".json"))
	if err != nil {
		return nil, false
	}
	var tiles map[string]int
	_ = json.Unmarshal(meta, &tiles)
	for i := range files {
		files[i].Tiles = tiles[files[i].Layer]
	}
	return files, true
}

// Path is where a pack file is stored; name comes from File.Name.
func (b *Builder) Path(name string) (string, bool) {
	if name == "" || strings.ContainsAny(name, `/\`) || !strings.HasSuffix(name, ".pmtiles") {
		return "", false
	}
	return filepath.Join(b.Dir, name), true
}

// Build writes the pack for tiles under key and removes older packs with
// the same prefix (older versions of the same route or journey).
// progress reports tiles done of all layers.
func (b *Builder) Build(ctx context.Context, key, prefix string, tiles []Tile, progress func(done, total int)) ([]File, error) {
	if len(tiles) > MaxTiles {
		return nil, ErrTooLarge
	}
	if err := os.MkdirAll(b.Dir, 0o750); err != nil {
		return nil, err
	}
	total := len(tiles) * len(Layers)
	var done int
	var mu sync.Mutex
	tick := func() {
		mu.Lock()
		done++
		d := done
		mu.Unlock()
		if progress != nil {
			progress(d, total)
		}
	}
	var files []File
	counts := map[string]int{}
	for _, l := range Layers {
		f, err := b.buildLayer(ctx, key, l, tiles, tick)
		if err != nil {
			return nil, err
		}
		files = append(files, f)
		counts[l.ID] = f.Tiles
	}
	meta, _ := json.Marshal(counts)
	if err := os.WriteFile(filepath.Join(b.Dir, key+".json"), meta, 0o640); err != nil {
		return nil, err
	}
	// Older versions of this pack are no longer needed.
	old, _ := filepath.Glob(filepath.Join(b.Dir, prefix+"*"))
	for _, p := range old {
		if !strings.HasPrefix(filepath.Base(p), key) {
			_ = os.Remove(p)
		}
	}
	return files, nil
}

type fetched struct {
	t    Tile
	data []byte
}

func (b *Builder) buildLayer(ctx context.Context, key string, l Layer, tiles []Tile, tick func()) (File, error) {
	name := key + "-" + l.ID + ".pmtiles"
	data, err := os.CreateTemp(b.Dir, name+".data-*")
	if err != nil {
		return File{}, err
	}
	defer func() { _ = os.Remove(data.Name()); _ = data.Close() }()

	jobs := make(chan Tile)
	results := make(chan fetched)
	errc := make(chan error, 1)
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	parallel := b.Parallel
	if parallel == 0 {
		parallel = 16
	}
	var wg sync.WaitGroup
	for range parallel {
		wg.Go(func() {
			for t := range jobs {
				body, err := b.fetch(ctx, l, t)
				if err != nil {
					select {
					case errc <- err:
					default:
					}
					cancel()
					return
				}
				select {
				case results <- fetched{t, body}:
				case <-ctx.Done():
					return
				}
			}
		})
	}
	go func() {
		defer close(jobs)
		for _, t := range tiles {
			select {
			case jobs <- t:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() { wg.Wait(); close(results) }()

	// Tiles are written as they arrive; identical tiles (e.g. empty trail
	// tiles) are stored once.
	var entries []entry
	byContent := map[[32]byte]entry{}
	var offset uint64
	for r := range results {
		tick()
		if r.data == nil {
			continue // no tile here
		}
		id := tileID(r.t.Z, r.t.X, r.t.Y)
		sum := sha256.Sum256(r.data)
		if e, ok := byContent[sum]; ok {
			entries = append(entries, entry{tileID: id, offset: e.offset, length: e.length, runLength: 1})
			continue
		}
		if _, err := data.Write(r.data); err != nil {
			return File{}, err
		}
		e := entry{tileID: id, offset: offset, length: uint32(len(r.data)), runLength: 1}
		byContent[sum] = e
		entries = append(entries, e)
		offset += uint64(len(r.data))
	}
	select {
	case err := <-errc:
		return File{}, err
	default:
	}
	if err := ctx.Err(); err != nil && !errors.Is(err, context.Canceled) {
		return File{}, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].tileID < entries[j].tileID })
	// Merge consecutive ids with the same content into runs.
	var runs []entry
	for _, e := range entries {
		if n := len(runs); n > 0 && runs[n-1].offset == e.offset && runs[n-1].tileID+uint64(runs[n-1].runLength) == e.tileID {
			runs[n-1].runLength++
			continue
		}
		runs = append(runs, e)
	}

	h := header{tileType: l.Type, minZoom: MinZoom, maxZoom: MaxZoom, dataLength: offset,
		addressedTiles: uint64(len(entries)), tileEntries: uint64(len(runs)), tileContents: uint64(len(byContent))}
	b.setBounds(&h, tiles)
	meta := gzipped([]byte(`{"attribution":"© swisstopo"}`))
	if _, err := data.Seek(0, io.SeekStart); err != nil {
		return File{}, err
	}
	out, err := os.CreateTemp(b.Dir, name+".tmp-*")
	if err != nil {
		return File{}, err
	}
	defer func() { _ = os.Remove(out.Name()) }()
	if err := writeArchive(out, h, runs, meta, data); err != nil {
		_ = out.Close()
		return File{}, err
	}
	st, _ := out.Stat()
	if err := out.Close(); err != nil {
		return File{}, err
	}
	if err := os.Rename(out.Name(), filepath.Join(b.Dir, name)); err != nil {
		return File{}, err
	}
	return File{Layer: l.ID, Name: name, Bytes: st.Size(), Tiles: len(entries)}, nil
}

func (b *Builder) setBounds(h *header, tiles []Tile) {
	minLon, minLat, maxLon, maxLat := 180.0, 90.0, -180.0, -90.0
	for _, t := range tiles {
		if t.Z != MaxZoom {
			continue
		}
		n := math.Exp2(float64(t.Z))
		w := float64(t.X)/n*360 - 180
		e := float64(t.X+1)/n*360 - 180
		north := math.Atan(math.Sinh(math.Pi*(1-2*float64(t.Y)/n))) * 180 / math.Pi
		south := math.Atan(math.Sinh(math.Pi*(1-2*float64(t.Y+1)/n))) * 180 / math.Pi
		minLon, maxLon = math.Min(minLon, w), math.Max(maxLon, e)
		minLat, maxLat = math.Min(minLat, south), math.Max(maxLat, north)
	}
	h.minLonE7, h.minLatE7 = int32(minLon*1e7), int32(minLat*1e7)
	h.maxLonE7, h.maxLatE7 = int32(maxLon*1e7), int32(maxLat*1e7)
	h.centerLonE7, h.centerLatE7 = int32((minLon+maxLon)/2*1e7), int32((minLat+maxLat)/2*1e7)
	h.centerZoom = 13
}

// fetch gets one tile; nil data means there is none (404, or outside the
// covered area).
func (b *Builder) fetch(ctx context.Context, l Layer, t Tile) ([]byte, error) {
	url := fmt.Sprintf("%s/tiles/wmts/%s/%d/%d/%d.%s", strings.TrimSuffix(b.TilesURL, "/"), l.WMTS, t.Z, t.X, t.Y, l.Ext)
	client := b.Client
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	for attempt := 0; ; attempt++ {
		if b.Rate != nil {
			if err := b.Rate.Wait(ctx); err != nil {
				return nil, err
			}
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, err
		}
		resp, err := client.Do(req)
		if err == nil {
			body, rerr := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
			_ = resp.Body.Close()
			switch {
			case rerr != nil:
				err = rerr
			case resp.StatusCode == http.StatusOK:
				return body, nil
			case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusNoContent:
				return nil, nil
			default:
				err = fmt.Errorf("packs: %s: HTTP %d", url, resp.StatusCode)
			}
		}
		if attempt == 3 || ctx.Err() != nil {
			return nil, err
		}
		time.Sleep(time.Duration(attempt+1) * 500 * time.Millisecond)
	}
}
