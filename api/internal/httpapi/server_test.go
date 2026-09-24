package httpapi

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/tellbow/odysgeh/api/internal/testdb"
)

func TestServerBasics(t *testing.T) {
	pool := testdb.New(t)
	handler, _ := New(Deps{DB: pool, Version: "test-sha"})
	srv := httptest.NewServer(handler)
	defer srv.Close()

	for _, path := range []string{"/healthz", "/readyz"} {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("%s: %d", path, resp.StatusCode)
		}
		if h := resp.Header.Get("X-Content-Type-Options"); h != "nosniff" {
			t.Errorf("%s: X-Content-Type-Options %q", path, h)
		}
	}

	var v struct{ Version, Source string }
	getJSON(t, srv.URL+"/api/v1/version", &v)
	if v.Version != "test-sha" || v.Source == "" {
		t.Errorf("version: %+v", v)
	}

	var spec struct {
		OpenAPI string         `json:"openapi"`
		Paths   map[string]any `json:"paths"`
	}
	getJSON(t, srv.URL+"/api/v1/openapi.json", &spec)
	if spec.OpenAPI != "3.1.0" || spec.Paths["/version"] == nil {
		t.Errorf("openapi: %s, paths %v", spec.OpenAPI, spec.Paths)
	}
}

func TestReadyzWithoutDatabase(t *testing.T) {
	pool := testdb.New(t)
	handler, _ := New(Deps{DB: pool})
	pool.Close() // simulate a lost database

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("readyz with closed pool: %d", rec.Code)
	}
}

func getJSON(t *testing.T, url string, v any) {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET %s: %d %s", url, resp.StatusCode, body)
	}
	if err := json.Unmarshal(body, v); err != nil {
		t.Fatalf("GET %s: %v: %s", url, err, body)
	}
}

func TestWriteDeadlineThroughMiddleware(t *testing.T) {
	// Long downloads extend their write deadline; the access log's recorder
	// must let that through.
	var got error
	h := withAccessLog(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		got = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(time.Minute))
	}))
	srv := httptest.NewServer(h)
	defer srv.Close()
	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if got != nil {
		t.Errorf("SetWriteDeadline: %v", got)
	}
}
