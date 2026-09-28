package places

import (
	"context"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

func TestPois(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	// A line 3.8 km east along 46.5° N (0.0013° ≈ 100 m).
	for _, p := range []struct {
		kind, name string
		ele        *int
		lon, lat   float64
	}{
		{"water", "", nil, 8.013, 46.5003},           // 1 km on, 33 m off
		{"peak", "Gipfel", ptr(2502), 8.026, 46.501}, // 2 km on, 110 m off
		{"viewpoint", "Aussicht", nil, 8.005, 46.5},  // 0.4 km on
		{"shelter", "Weit weg", nil, 8.02, 46.51},    // 1.1 km off
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO pois (kind, name, ele, source_id, geom)
			VALUES ($1, $2, $3, $1 || $2, ST_SetSRID(ST_MakePoint($4, $5), 4326))`, p.kind, p.name, p.ele, p.lon, p.lat); err != nil {
			t.Fatal(err)
		}
	}
	s := &Store{DB: pool}
	got, err := s.Along(ctx, []geo.Point{{Lon: 8.0, Lat: 46.5}, {Lon: 8.05, Lat: 46.5}})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 || got[0].Kind != "viewpoint" || got[1].Kind != "water" || got[2].Name != "Gipfel" {
		t.Fatalf("along: %+v", got)
	}
	if p := got[2]; *p.Ele != 2502 || p.AlongM < 1950 || p.AlongM > 2050 || p.OffM < 100 || p.OffM > 120 {
		t.Errorf("summit: %+v", p)
	}

	// On the map with the huts.
	pins, err := s.InView(ctx, 7.9, 46.4, 8.1, 46.6, []string{"peak", "shelter"})
	if err != nil || len(pins) != 2 {
		t.Fatalf("in view: %+v %v", pins, err)
	}
	for _, p := range pins {
		if p.Kind == "peak" && p.Detail != "2502" {
			t.Errorf("summit pin: %+v", p)
		}
	}
}

func ptr(v int) *int { return &v }
