package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/api/internal/packs"
)

type packResp struct {
	State string `json:"state"`
	Key   string `json:"key"`
	Files []struct {
		Layer string `json:"layer"`
		Tiles int    `json:"tiles"`
	} `json:"files"`
}

func (c *client) pack(method, path string) (int, packResp) {
	c.t.Helper()
	code, raw := c.do(method, path, nil)
	var out packResp
	_ = json.Unmarshal(raw, &out)
	return code, out
}

// waitPack polls the pack status of item while it is building.
func (c *client) waitPack(item string, st packResp) packResp {
	c.t.Helper()
	for deadline := time.Now().Add(10 * time.Second); st.State == "building" && time.Now().Before(deadline); {
		time.Sleep(20 * time.Millisecond)
		_, st = c.pack("GET", item+"/pack")
	}
	return st
}

func TestPacks(t *testing.T) {
	var fetched atomic.Int64
	tiles := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fetched.Add(1)
		_, _ = w.Write([]byte("tile " + r.URL.Path))
	}))
	t.Cleanup(tiles.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Packs = &packs.Service{Builder: &packs.Builder{TilesURL: tiles.URL, Dir: t.TempDir()}}
	})
	owner, stranger, anon := s.client(t), s.client(t), s.client(t)
	owner.do("POST", "/api/v1/auth/signup", signupBody("owner@example.ch", "owner"))
	stranger.do("POST", "/api/v1/auth/signup", signupBody("str@example.ch", "str"))
	_, body := owner.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var route savedRoute
	_ = json.Unmarshal(body, &route)
	r := "/api/v1/routes/" + route.ID

	if code, _ := anon.pack("POST", r+"/pack"); code != http.StatusUnauthorized {
		t.Errorf("anonymous build: %d, want 401", code)
	}
	if code, _ := stranger.pack("POST", r+"/pack"); code != http.StatusNotFound {
		t.Errorf("build of someone else's private route: %d, want 404", code)
	}
	if code, st := owner.pack("GET", r+"/pack"); code != http.StatusOK || st.State != "missing" {
		t.Fatalf("status before: %d %+v", code, st)
	}
	if code, _ := owner.do("GET", r+"/pack/landeskarte", nil); code != http.StatusNotFound {
		t.Errorf("download before building: %d, want 404", code)
	}
	code, st := owner.pack("POST", r+"/pack")
	if code != http.StatusOK || st.State != "building" {
		t.Fatalf("build: %d %+v", code, st)
	}
	st = owner.waitPack(r, st)
	if st.State != "ready" || len(st.Files) != 2 || st.Files[0].Tiles == 0 {
		t.Fatalf("after building: %+v", st)
	}
	n := fetched.Load()

	// Again: the same pack, nothing fetched.
	if _, again := owner.pack("POST", r+"/pack"); again.State != "ready" || again.Key != st.Key || fetched.Load() != n {
		t.Errorf("second build: %+v, %d more tiles fetched", again, fetched.Load()-n)
	}

	// The file is PMTiles v3, and downloads can resume.
	code, raw := owner.do("GET", r+"/pack/wanderwege", nil, "Range", "bytes=0-7")
	if code != http.StatusPartialContent || !bytes.Equal(raw, []byte("PMTiles\x03")) {
		t.Errorf("range download: %d %q", code, raw)
	}
	if code, _ := stranger.do("GET", r+"/pack/wanderwege", nil); code != http.StatusNotFound {
		t.Errorf("stranger downloads: %d, want 404", code)
	}

	// A new title keeps the pack; a new line needs a new one.
	owner.do("PATCH", r, map[string]any{"title": "Grat"}, "If-Match", `"1"`)
	if _, after := owner.pack("GET", r+"/pack"); after.State != "ready" || after.Key != st.Key {
		t.Errorf("after renaming: %+v", after)
	}
	moved := newRouteBody("Grat", "private")
	moved["anchors"] = []map[string]any{{"lon": 8.01, "lat": 46.5}, {"lon": 8.012, "lat": 46.5}, {"lon": 8.014, "lat": 46.5}}
	moved["legs"] = []map[string]any{routeLeg(8.01), routeLeg(8.012)}
	if code, body := owner.do("PATCH", r, moved, "If-Match", `"2"`); code != http.StatusOK {
		t.Fatalf("move the route: %d %s", code, body)
	}
	if _, after := owner.pack("GET", r+"/pack"); after.State != "missing" || after.Key == st.Key {
		t.Errorf("after moving: %+v", after)
	}

	// Journeys: one pack for all stages.
	_, body = owner.do("POST", "/api/v1/journeys", map[string]any{"title": "Via Alpina", "visibility": "private"})
	j := decodeJourney(t, body)
	jr := "/api/v1/journeys/" + j.ID
	if code, _ := owner.pack("POST", jr+"/pack"); code != http.StatusUnprocessableEntity {
		t.Errorf("journey without stages: %d, want 422", code)
	}
	_, body = owner.do("POST", jr+"/stages", map[string]any{})
	j = decodeJourney(t, body)
	owner.do("POST", jr+"/stages/"+j.StageList[0].ID+"/route", stageRouteBody(8.0))
	code, st = owner.pack("POST", jr+"/pack")
	if st = owner.waitPack(jr, st); code != http.StatusOK || st.State != "ready" {
		t.Errorf("journey build: %d %+v", code, st)
	}
}
