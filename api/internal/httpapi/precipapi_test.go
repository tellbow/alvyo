package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestPrecipitation(t *testing.T) {
	s := newTestServer(t, Limits{})
	anon := s.client(t)
	now := time.Now().UTC().Truncate(time.Minute)
	frame := func(kind string, at time.Time, png string) {
		t.Helper()
		if _, err := s.db.Exec(context.Background(), `INSERT INTO precip_frames (kind, valid_at, png, west, south, east, north)
			VALUES ($1, $2, $3, 2.689, 43.619, 12.462, 49.374)`, kind, at, []byte(png)); err != nil {
			t.Fatal(err)
		}
	}
	var tl struct {
		Bounds struct{ West, North float64 }
		Frames []struct {
			Kind string
			Time time.Time
			URL  string
		}
		Legend []struct {
			From  float64
			Color string
		}
		Attribution string
	}
	get := func() {
		t.Helper()
		code, body := anon.do("GET", "/api/v1/weather/precip", nil)
		if err := json.Unmarshal(body, &tl); err != nil || code != http.StatusOK {
			t.Fatalf("timeline: %d %s", code, body)
		}
	}

	get()
	if len(tl.Frames) != 0 || len(tl.Legend) == 0 {
		t.Fatalf("without pictures: %+v", tl)
	}

	newest := now.Add(-10 * time.Minute)
	frame("radar", newest.Add(-5*time.Minute), "r1")
	frame("radar", newest, "r2")
	frame("forecast", newest.Add(-time.Hour), "old")     // before the newest radar picture
	frame("forecast", now.Add(time.Hour), "f1")          // the next hour
	frame("forecast", now.Add(2*time.Hour), "f2")        //
	frame("forecast", now.Add(13*time.Hour), "too late") // beyond 12 hours
	get()
	var kinds []string
	for _, f := range tl.Frames {
		kinds = append(kinds, f.Kind)
	}
	if strings.Join(kinds, ",") != "radar,radar,forecast,forecast" || !tl.Frames[1].Time.Equal(newest) ||
		tl.Bounds.West != 2.689 || tl.Bounds.North != 49.374 || tl.Attribution != "MeteoSchweiz" {
		t.Fatalf("timeline %+v", tl)
	}

	code, body := anon.do("GET", tl.Frames[3].URL, nil)
	if code != http.StatusOK || string(body) != "f2" {
		t.Errorf("picture: %d %s", code, body)
	}
	if code, _ := anon.do("GET", "/api/v1/weather/precip/radar/1/frame.png", nil); code != http.StatusNotFound {
		t.Errorf("missing picture: %d", code)
	}
}
