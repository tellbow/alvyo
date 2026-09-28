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
	way := JourneyTravel{To: &Way{HomeID: thun.ID, Time: "06:00"}, Back: &Way{HomeID: thun.ID, Time: "20:00", Arrive: true}}
	if err := s.Set(ctx, anna, journey, way); err != nil {
		t.Fatal(err)
	}
	if err := s.Set(ctx, bea, journey, JourneyTravel{To: &Way{HomeID: thun.ID, Time: "07:00"}}); !errors.Is(err, ErrNotFound) {
		t.Errorf("bea with anna's home: %v", err)
	}
	got, _ := s.Of(ctx, anna, journey)
	if got.To == nil || got.To.Time != "06:00" || got.To.Arrive || got.Back == nil || !got.Back.Arrive {
		t.Errorf("anna's travel %+v %+v", got.To, got.Back)
	}
	if got, _ := s.Of(ctx, bea, journey); got.To != nil || got.Back != nil {
		t.Errorf("bea's travel %+v", got)
	}
	if err := s.Set(ctx, anna, journey, JourneyTravel{To: &Way{HomeID: thun.ID, Time: "8:00"}}); err == nil {
		t.Error("time without leading zero accepted")
	}

	// Only to the start now; then the home goes, and its travel with it.
	if err := s.Set(ctx, anna, journey, JourneyTravel{To: way.To}); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Of(ctx, anna, journey); got.Back != nil {
		t.Errorf("back kept: %+v", got.Back)
	}
	if err := s.DeleteHome(ctx, bea, uuid.MustParse(thun.ID)); !errors.Is(err, ErrNotFound) {
		t.Errorf("bea deletes anna's home: %v", err)
	}
	if err := s.DeleteHome(ctx, anna, uuid.MustParse(thun.ID)); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Of(ctx, anna, journey); got.To != nil {
		t.Errorf("travel from a deleted home: %+v", got.To)
	}
}
