package travel

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/google/uuid"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestHomesAndTravel(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	s := &Store{DB: pool}
	user := func(name string) uuid.UUID {
		var id uuid.UUID
		if err := pool.QueryRow(ctx, `INSERT INTO users (email, username, display_name, locale)
			VALUES ($1 || '@example.ch', $1, $1, 'de') RETURNING id`, name).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	anna, bea := user("anna"), user("bea")
	var journey uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO journeys (owner_id, title) VALUES ($1, 'Spiez – Zermatt') RETURNING id`, anna).Scan(&journey); err != nil {
		t.Fatal(err)
	}

	thun, err := s.AddHome(ctx, anna, Home{Name: "Zuhause", Address: "Länggasse 13B, 3600 Thun", Lon: 7.6197, Lat: 46.764})
	if err != nil {
		t.Fatal(err)
	}
	for i := range MaxHomes - 1 {
		if _, err := s.AddHome(ctx, anna, Home{Name: fmt.Sprint(i), Address: "x", Lon: 7, Lat: 46}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.AddHome(ctx, anna, Home{Name: "one more", Address: "x", Lon: 7, Lat: 46}); !errors.Is(err, ErrTooMany) {
		t.Errorf("sixth home: %v", err)
	}
	homes, _ := s.Homes(ctx, anna)
	if len(homes) != MaxHomes || homes[0].Address != "Länggasse 13B, 3600 Thun" {
		t.Errorf("homes %+v", homes)
	}
	if others, _ := s.Homes(ctx, bea); len(others) != 0 {
		t.Errorf("bea sees %+v", others)
	}

	// Each person's own travel; not with someone else's home.
	way := Travel{To: &Way{HomeID: thun.ID, Time: "06:00"}, Back: &Way{HomeID: thun.ID, Time: "20:00", Arrive: true}}
	if err := s.Set(ctx, Journey, anna, journey, way); err != nil {
		t.Fatal(err)
	}
	if err := s.Set(ctx, Journey, bea, journey, Travel{To: &Way{HomeID: thun.ID, Time: "07:00"}}); !errors.Is(err, ErrNotFound) {
		t.Errorf("bea with anna's home: %v", err)
	}
	got, _ := s.Of(ctx, Journey, anna, journey)
	if got.To == nil || got.To.Time != "06:00" || got.To.Arrive || got.Back == nil || !got.Back.Arrive {
		t.Errorf("anna's travel %+v %+v", got.To, got.Back)
	}
	if got, _ := s.Of(ctx, Journey, bea, journey); got.To != nil || got.Back != nil {
		t.Errorf("bea's travel %+v", got)
	}
	if err := s.Set(ctx, Journey, anna, journey, Travel{To: &Way{HomeID: thun.ID, Time: "8:00"}}); err == nil {
		t.Error("time without leading zero accepted")
	}

	// Only to the start now; then the home goes, and its travel with it.
	if err := s.Set(ctx, Journey, anna, journey, Travel{To: way.To}); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Of(ctx, Journey, anna, journey); got.Back != nil {
		t.Errorf("back kept: %+v", got.Back)
	}
	if err := s.DeleteHome(ctx, bea, uuid.MustParse(thun.ID)); !errors.Is(err, ErrNotFound) {
		t.Errorf("bea deletes anna's home: %v", err)
	}
	if err := s.DeleteHome(ctx, anna, uuid.MustParse(thun.ID)); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Of(ctx, Journey, anna, journey); got.To != nil {
		t.Errorf("travel from a deleted home: %+v", got.To)
	}

	// From anywhere: a place instead of a home, for a journey and a route.
	bern := &Spot{Name: "Bern, Bahnhof", Lon: 7.4391, Lat: 46.9490}
	if err := s.Set(ctx, Journey, anna, journey, Travel{To: &Way{Place: bern, Time: "07:30"}}); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Of(ctx, Journey, anna, journey); got.To == nil || got.To.HomeID != "" || *got.To.Place != *bern {
		t.Errorf("from a place: %+v", got.To)
	}
	var route uuid.UUID
	if err := pool.QueryRow(ctx, `INSERT INTO routes (owner_id, title, anchors, legs, geom, distance_m, ascent_m, descent_m,
			duration_s, duration_reverse_s, ele_min_m, ele_max_m, sac_grade, sac_max)
		VALUES ($1, 'Gantrisch', '[]', '[]', ST_GeomFromText('LINESTRING Z (7.4 46.7 1500, 7.401 46.7 1500)', 4326), 1, 1, 1, 1, 1, 1, 1, 1, 1)
		RETURNING id`, anna).Scan(&route); err != nil {
		t.Fatal(err)
	}
	spiez, err := s.AddHome(ctx, anna, Home{Name: "Spiez", Address: "x", Lon: 7.68, Lat: 46.69})
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Set(ctx, Route, anna, route, Travel{To: &Way{HomeID: spiez.ID, Time: "08:00"}, Back: &Way{Place: bern, Time: "18:00", Arrive: true}}); err != nil {
		t.Fatal(err)
	}
	got, _ = s.Of(ctx, Route, anna, route)
	if got.To == nil || got.To.HomeID != spiez.ID || got.Back == nil || got.Back.Place == nil || !got.Back.Arrive {
		t.Errorf("route travel %+v %+v", got.To, got.Back)
	}
	if got, _ := s.Of(ctx, Journey, anna, route); got.To != nil {
		t.Errorf("a route's travel as a journey's: %+v", got.To)
	}
	if err := s.Set(ctx, Route, anna, route, Travel{To: &Way{HomeID: spiez.ID, Place: bern, Time: "08:00"}}); err == nil {
		t.Error("home and place at once accepted")
	}
}
