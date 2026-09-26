package places

import (
	"context"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestNearby(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	for _, p := range []struct {
		kind, name string
		lon        float64
	}{
		{"pt_stop", "Sargans", 9.4460},       // ~0 m
		{"pt_stop", "Sargans, Rose", 9.4500}, // ~300 m
		{"hut", "Hütte", 9.4600},             // ~1 km
		{"pt_stop", "Mels, Dorf", 9.4900},    // ~3.3 km: only found by name
		{"pt_stop", "Sargans, Fern", 9.8500}, // ~30.7 km: never
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'didok', $2, ST_SetSRID(ST_MakePoint($3, 47.045), 4326))`, p.kind, p.name, p.lon); err != nil {
			t.Fatal(err)
		}
	}
	s := &Store{DB: pool}
	names := func(q Query) []string {
		t.Helper()
		ps, err := s.Nearby(ctx, q)
		if err != nil {
			t.Fatal(err)
		}
		out := []string{}
		for _, p := range ps {
			out = append(out, p.Name)
		}
		return out
	}
	for _, tc := range []struct {
		name string
		q    Query
		want []string
	}{
		{"nearest first within 3 km", Query{Lon: 9.446, Lat: 47.045}, []string{"Sargans", "Sargans, Rose", "Hütte"}},
		{"by kind", Query{Lon: 9.446, Lat: 47.045, Kinds: []string{"hut"}}, []string{"Hütte"}},
		{"by name, wider", Query{Lon: 9.446, Lat: 47.045, Name: "mels"}, []string{"Mels, Dorf"}},
		{"limit", Query{Lon: 9.446, Lat: 47.045, Limit: 1}, []string{"Sargans"}},
		{"name within 30 km", Query{Lon: 9.446, Lat: 47.045, Name: "sargans"}, []string{"Sargans", "Sargans, Rose"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := names(tc.q)
			if len(got) != len(tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("got %v, want %v", got, tc.want)
				}
			}
		})
	}
}

func TestInView(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	for _, p := range []struct {
		kind, name string
		lon        float64
	}{
		{"hut", "Inside", 9.0},
		{"hotel", "Hotel", 9.1},
		{"hut", "Outside", 9.5},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, website, geom)
			VALUES ($1, $2, 'osm', $2, 'https://example.ch', ST_SetSRID(ST_MakePoint($3, 46.5), 4326))`, p.kind, p.name, p.lon); err != nil {
			t.Fatal(err)
		}
	}
	s := &Store{DB: pool}
	ps, err := s.InView(ctx, 8.9, 46.4, 9.2, 46.6, []string{"hut"})
	if err != nil {
		t.Fatal(err)
	}
	if len(ps) != 1 || ps[0].Name != "Inside" || ps[0].Website != "https://example.ch" || ps[0].Lon != 9.0 || ps[0].Lat != 46.5 {
		t.Fatalf("got %+v", ps)
	}
}
