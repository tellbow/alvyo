package packs

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/swiss/geo"
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
	files, err := b.Build(context.Background(), Key("route", "r1", v1), "route-r1-", want, func(done, _ int) { last = done })
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
	if _, err := b.Build(context.Background(), Key("route", "r1", v2), "route-r1-", want[:3], nil); err != nil {
		t.Fatal(err)
	}
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
