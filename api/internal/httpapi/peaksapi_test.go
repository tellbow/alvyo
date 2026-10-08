package httpapi

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"net/http"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/peaks"
)

func TestPeaksPack(t *testing.T) {
	// Terrain 1500 m everywhere.
	tile := func(context.Context, int, int) (image.Image, error) {
		v := 1500 + 32768
		return image.NewUniform(color.NRGBA{R: uint8(v >> 8), G: uint8(v), A: 255}), nil
	}
	s := newTestServerWith(t, func(d *Deps) {
		d.Peaks = &peaks.Service{DB: d.DB, Dir: t.TempDir(), Tile: tile}
	})
	if _, err := s.db.Exec(context.Background(), `INSERT INTO pois (kind, name, ele, source_id, geom) VALUES
		('peak', 'Pilatus', 2128, 'n1', ST_Point(8.2541, 46.9792, 4326)),
		('peak', '', 1800, 'n2', ST_Point(8.3, 46.9, 4326)),
		('viewpoint', 'Aussicht', 1500, 'n3', ST_Point(8.31, 46.91, 4326))`); err != nil {
		t.Fatal(err)
	}

	if code, _ := s.client(t).do("GET", "/api/v1/peaks/pack", nil); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	c := s.client(t)
	s.signup(c, "anna@example.ch", "anna")
	code, body := c.do("GET", "/api/v1/peaks/pack", nil)
	for end := time.Now().Add(time.Minute); code == http.StatusServiceUnavailable && time.Now().Before(end); {
		time.Sleep(200 * time.Millisecond)
		code, body = c.do("GET", "/api/v1/peaks/pack", nil)
	}
	if code != http.StatusOK {
		t.Fatalf("pack: %d %.200s", code, body)
	}
	p, err := peaks.Read(bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Peaks) != 1 || p.Peaks[0].Name != "Pilatus" || p.Peaks[0].Ele != 2128 {
		t.Errorf("only the named summits: %+v", p.Peaks)
	}
	if h := p.Height(8.2541, 46.9792); h != 1500 {
		t.Errorf("height %d", h)
	}
}
