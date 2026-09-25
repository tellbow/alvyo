package packs

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// readEntries decodes a directory (the inverse of serializeEntries).
func readEntries(t *testing.T, b []byte) []entry {
	t.Helper()
	zr, err := gzip.NewReader(bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(zr)
	r := bytes.NewReader(raw)
	n, _ := binary.ReadUvarint(r)
	es := make([]entry, n)
	last := uint64(0)
	for i := range es {
		d, _ := binary.ReadUvarint(r)
		last += d
		es[i].tileID = last
	}
	for i := range es {
		v, _ := binary.ReadUvarint(r)
		es[i].runLength = uint32(v)
	}
	for i := range es {
		v, _ := binary.ReadUvarint(r)
		es[i].length = uint32(v)
	}
	for i := range es {
		v, _ := binary.ReadUvarint(r)
		if v == 0 && i > 0 {
			es[i].offset = es[i-1].offset + uint64(es[i-1].length)
		} else {
			es[i].offset = v - 1
		}
	}
	return es
}

func TestTileID(t *testing.T) {
	// Values from the PMTiles specification.
	for _, c := range []struct {
		z    uint8
		x, y uint32
		id   uint64
	}{{0, 0, 0, 0}, {1, 0, 0, 1}, {1, 0, 1, 2}, {1, 1, 1, 3}, {1, 1, 0, 4}, {2, 0, 0, 5}} {
		if got := tileID(c.z, c.x, c.y); got != c.id {
			t.Errorf("tileID(%d,%d,%d) = %d, want %d", c.z, c.x, c.y, got, c.id)
		}
	}
}

func TestCorridor(t *testing.T) {
	// 5 km east at 46.5° N.
	line := []geo.Point{{Lon: 8, Lat: 46.5}, {Lon: 8.065, Lat: 46.5}}
	tiles := Corridor([][]geo.Point{line}, BufferM)
	perZoom := map[uint8]int{}
	for _, tl := range tiles {
		perZoom[tl.Z]++
	}
	// At z16 a tile is ~420 m: a 7 km × 2 km corridor is ~17 × 5–6 tiles;
	// at z10 (27 km) one or two tiles.
	if perZoom[16] < 80 || perZoom[16] > 130 || perZoom[10] > 2 {
		t.Errorf("tiles per zoom: %v", perZoom)
	}
}

func TestBuild(t *testing.T) {
	var requests atomic.Int32
	tiles := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if strings.Contains(r.URL.Path, "wanderwege") {
			// Most trail tiles are empty: all the same bytes.
			_, _ = w.Write([]byte("empty-png"))
			return
		}
		if strings.HasSuffix(r.URL.Path, "/16/34200/23184.jpeg") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte("jpeg:" + r.URL.Path))
	}))
	defer tiles.Close()
	dir := t.TempDir()
	b := &Builder{TilesURL: tiles.URL, Dir: dir, Parallel: 4}

	line := []geo.Point{{Lon: 7.9, Lat: 46.6}, {Lon: 7.95, Lat: 46.61}}
	want := Corridor([][]geo.Point{line}, BufferM)
	v1, v2 := [][]geo.Point{line}, [][]geo.Point{line[:1]}
	var last int
	files, err := b.Build(context.Background(), Key("route", "r1", v1), want, func(done, _ int) { last = done })
	if err != nil {
		t.Fatal(err)
	}
	if last != 2*len(want) || int(requests.Load()) != 2*len(want) {
		t.Errorf("progress %d, requests %d, want %d", last, requests.Load(), 2*len(want))
	}
	if len(files) != 2 || files[1].Tiles != len(want) {
		t.Fatalf("files: %+v", files)
	}

	// Read the landeskarte archive back.
	raw, err := os.ReadFile(filepath.Join(dir, files[0].Name))
	if err != nil {
		t.Fatal(err)
	}
	le := binary.LittleEndian
	if string(raw[:7]) != "PMTiles" || raw[7] != 3 || raw[99] != tileJPEG || raw[100] != MinZoom || raw[101] != MaxZoom {
		t.Fatalf("header %q v%d type %d zoom %d–%d", raw[:7], raw[7], raw[99], raw[100], raw[101])
	}
	rootOff, rootLen := le.Uint64(raw[8:]), le.Uint64(raw[16:])
	dataOff := le.Uint64(raw[56:])
	entries := readEntries(t, raw[rootOff:rootOff+rootLen])
	byID := map[uint64]entry{}
	for _, e := range entries {
		byID[e.tileID] = e
	}
	for _, tl := range want {
		e, ok := byID[tileID(tl.Z, tl.X, tl.Y)]
		path := fmt.Sprintf("/tiles/wmts/ch.swisstopo.pixelkarte-farbe/%d/%d/%d.jpeg", tl.Z, tl.X, tl.Y)
		if strings.HasSuffix(path, "/16/34200/23184.jpeg") {
			if ok {
				t.Error("missing tile stored")
			}
			continue
		}
		if !ok {
			t.Fatalf("tile %v not in the directory", tl)
		}
		if got := string(raw[dataOff+e.offset : dataOff+e.offset+uint64(e.length)]); got != "jpeg:"+path {
			t.Fatalf("tile %v holds %q", tl, got)
		}
	}

	// The trail archive stores the one empty tile once, as runs.
	raw, _ = os.ReadFile(filepath.Join(dir, files[1].Name))
	if contents := le.Uint64(raw[88:]); contents != 1 {
		t.Errorf("trail tile contents %d, want 1", contents)
	}

	// A new version replaces the old files.
	if _, err := b.Build(context.Background(), Key("route", "r1", v2), want[:3], nil); err != nil {
		t.Fatal(err)
	}
	b.RemoveOthers(Key("route", "r1", v2), "route-r1-")
	if _, ok := b.Existing(Key("route", "r1", v1)); ok {
		t.Error("old version still there")
	}
	if f, ok := b.Existing(Key("route", "r1", v2)); !ok || f[0].Tiles != 3 {
		t.Errorf("new version: %+v %v", f, ok)
	}
}

func TestPrune(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	write := func(name string, size int, age time.Duration) {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, make([]byte, size), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(p, now.Add(-age), now.Add(-age)); err != nil {
			t.Fatal(err)
		}
	}
	write("stale.pmtiles", 10, 8*24*time.Hour)
	write("old.pmtiles", 100, 3*time.Hour)
	write("recent.pmtiles", 100, 2*time.Hour)
	write("new.pmtiles", 100, time.Minute)
	left := func() []string {
		entries, _ := os.ReadDir(dir)
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		return names
	}

	(&Service{Builder: &Builder{Dir: dir}}).Prune() // no limits
	if n := len(left()); n != 4 {
		t.Fatalf("without limits %d files left, want 4", n)
	}
	(&Service{Builder: &Builder{Dir: dir}, MaxAge: 7 * 24 * time.Hour, MaxBytes: 250}).Prune()
	if got := strings.Join(left(), " "); got != "new.pmtiles recent.pmtiles" {
		t.Errorf("left %q, want the two most recently used", got)
	}
}

func TestBuildTwiceSameFile(t *testing.T) {
	// Tiles arrive in any order; the file is the same, so that a download
	// broken off before a rebuild resumes on the same bytes.
	tiles := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(time.Duration(rand.IntN(3)) * time.Millisecond)
		_, _ = w.Write([]byte("tile:" + r.URL.Path))
	}))
	defer tiles.Close()
	want := Corridor([][]geo.Point{{{Lon: 7.9, Lat: 46.6}, {Lon: 7.95, Lat: 46.61}}}, BufferM)
	var files [2][]byte
	for i := range files {
		dir := t.TempDir()
		built, err := (&Builder{TilesURL: tiles.URL, Dir: dir, Parallel: 8}).Build(context.Background(), "route-r1-abc", want, nil)
		if err != nil {
			t.Fatal(err)
		}
		files[i], _ = os.ReadFile(filepath.Join(dir, built[0].Name))
	}
	if !bytes.Equal(files[0], files[1]) {
		t.Error("two builds of the same pack differ")
	}
}

func TestPrunePacksWhole(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	write := func(name string, size int, age time.Duration) {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, make([]byte, size), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(p, now.Add(-age), now.Add(-age)); err != nil {
			t.Fatal(err)
		}
	}
	day := 24 * time.Hour
	// Downloaded yesterday (its map touched), built 8 days ago: kept whole.
	write("route-a-1.json", 10, 8*day)
	write("route-a-1-landeskarte.pmtiles", 100, day)
	write("route-a-1-wanderwege.pmtiles", 100, 8*day)
	// Not used for 8 days: all its files go.
	write("route-b-1.json", 10, 8*day)
	write("route-b-1-landeskarte.pmtiles", 100, 8*day)
	// A build under way, and one that crashed long ago.
	write("route-c-2-landeskarte.pmtiles.tmp-123", 100, time.Minute)
	write("route-d-1-landeskarte.pmtiles.data-456", 100, 3*time.Hour)
	// Just built, bigger than the budget on its own: kept while in use.
	write("route-e-1.json", 10, time.Minute)
	write("route-e-1-landeskarte.pmtiles", 1000, time.Minute)

	left := func() string {
		entries, _ := os.ReadDir(dir)
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		return strings.Join(names, " ")
	}
	(&Service{Builder: &Builder{Dir: dir}, MaxAge: 7 * day}).Prune()
	if got, want := left(), "route-a-1-landeskarte.pmtiles route-a-1-wanderwege.pmtiles route-a-1.json "+
		"route-c-2-landeskarte.pmtiles.tmp-123 route-e-1-landeskarte.pmtiles route-e-1.json"; got != want {
		t.Errorf("by age: left %s\nwant %s", got, want)
	}
	// Over the budget: the least recently used pack goes, the one in use stays.
	(&Service{Builder: &Builder{Dir: dir}, MaxAge: 7 * day, MaxBytes: 500}).Prune()
	if got, want := left(), "route-c-2-landeskarte.pmtiles.tmp-123 route-e-1-landeskarte.pmtiles route-e-1.json"; got != want {
		t.Errorf("by size: left %s\nwant %s", got, want)
	}
}

func TestOlderBuildKeepsNewer(t *testing.T) {
	// The route is changed while its first pack builds: the first build,
	// finishing last, must not remove the pack of the new version.
	tiles := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("tile"))
	}))
	defer tiles.Close()
	s := &Service{Builder: &Builder{TilesURL: tiles.URL, Dir: t.TempDir()}}
	few := []Tile{{Z: 16, X: 34200, Y: 23184}}
	release := make(chan struct{})
	s.Ensure("route-r1-old", "route-r1-", func(context.Context) ([]Tile, error) {
		<-release // still working out its tiles
		return few, nil
	})
	s.Ensure("route-r1-new", "route-r1-", func(context.Context) ([]Tile, error) { return few, nil })
	wait := func(key string) {
		t.Helper()
		for range 500 {
			if s.Status(key).State == "ready" {
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatalf("%s: %+v", key, s.Status(key))
	}
	wait("route-r1-new")
	close(release)
	wait("route-r1-old")
	if st := s.Status("route-r1-new"); st.State != "ready" {
		t.Errorf("new version after the old build: %+v", st)
	}
}
