package places

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
)

func TestParseLabel(t *testing.T) {
	for _, c := range []struct{ label, name, detail string }{
		{"<i>Hauptgipfel</i> <b>Brisen</b> (UR) - Isenthal", "Brisen", "Hauptgipfel, Isenthal (UR)"},
		{"<b>Gitsch</b> (BE) - Lauterbrunnen", "Gitsch", "Lauterbrunnen (BE)"},
		{"<i>Pass</i> <b>Eggen|Surenenpass</b> (UR) - Attinghausen", "Eggen / Surenenpass", "Pass, Attinghausen (UR)"},
		{"<i>Ort</i> <b>Büsingen am Hochrhein</b> () - Büsingen am Hochrhein", "Büsingen am Hochrhein", "Ort, Büsingen am Hochrhein"},
		{"Seestrasse 1 <b>6375 Beckenried</b>", "Seestrasse 1, 6375 Beckenried", ""},
		{"<b>Caf&eacute; <script>x</script></b>", "Café x", ""},
		// The line broken inside the name, as for some towns.
		{"<b>Genève\n</b> (GE) - Genève,Cologny", "Genève", "Genève,Cologny (GE)"},
	} {
		name, detail := parseLabel(c.label)
		if name != c.name || detail != c.detail {
			t.Errorf("parseLabel(%q) = %q, %q; want %q, %q", c.label, name, detail, c.name, c.detail)
		}
	}
}

// searchServer answers with a recorded SearchServer response.
func searchServer(t *testing.T, check func(*http.Request)) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		check(r)
		file := "testdata/searchserver-brisen.json"
		if r.URL.Query().Get("searchText") == "Seestrasse 1 Beckenried" {
			file = "testdata/searchserver-address.json"
		}
		b, err := os.ReadFile(file)
		if err != nil {
			t.Error(err)
		}
		_, _ = w.Write(b)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestGeoAdmin(t *testing.T) {
	var origins string
	srv := searchServer(t, func(r *http.Request) {
		q := r.URL.Query()
		origins = q.Get("origins")
		if q.Get("sr") != "4326" || q.Get("lang") != "fr" || q.Get("type") != "locations" {
			t.Errorf("query %v", q)
		}
	})
	g := &GeoAdmin{URL: srv.URL}

	names, err := g.Search(context.Background(), "brisen", "fr")
	if err != nil {
		t.Fatal(err)
	}
	if origins != "gazetteer" {
		t.Errorf("origins %q: addresses only with a house number", origins)
	}
	if len(names) != 9 || names[0].Name != "Brisen" || names[0].Kind != "name" || names[0].At[0] < 8.4 || names[0].At[1] < 46.8 {
		t.Fatalf("names %+v", names)
	}

	addresses, err := g.Search(context.Background(), "Seestrasse 1 Beckenried", "fr")
	if err != nil {
		t.Fatal(err)
	}
	if origins != "gazetteer,address" || addresses[0].Name != "Seestrasse 1, 6375 Beckenried" || addresses[0].Kind != "address" {
		t.Errorf("origins %q, addresses %+v", origins, addresses)
	}
}

type failingNames struct{}

func (failingNames) Search(context.Context, string, string) ([]Found, error) {
	return nil, errors.New("down")
}

func TestSearch(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	for _, p := range []struct {
		kind, name string
		lon, lat   float64
	}{
		{"hut", "Brisenhaus", 8.4642, 46.9150},
		{"pt_stop", "Welschenrohr, Brisenmatt", 7.5310, 47.2800},
		{"pt_stop", "Brisen, Talstation", 7.0000, 46.5000}, // far from the map centre
		{"pt_stop", "Brisen, Bergstation", 8.5000, 46.9000},
		{"pt_stop", "Sargans", 9.4460, 47.0450},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ($1, $2, 'didok', $2, ST_SetSRID(ST_MakePoint($3, $4), 4326))`, p.kind, p.name, p.lon, p.lat); err != nil {
			t.Fatal(err)
		}
	}
	srv := searchServer(t, func(*http.Request) {})
	s := &Store{DB: pool, Names: &GeoAdmin{URL: srv.URL}}
	near := [2]float64{8.5, 46.9}

	got, err := s.Search(ctx, "brisen", near, "de")
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, f := range got {
		names = append(names, f.Name)
	}
	// The name just as searched first (swisstopo's summit); then ours: whole
	// words first, then the nearer of two equal matches. swisstopo's two
	// "Brisenhaus" buildings repeat our hut, and its "Brisenmatt" the stop
	// there.
	want := []string{
		"Brisen", "Brisen, Bergstation", "Brisen, Talstation", "Brisenhaus", "Welschenrohr, Brisenmatt",
		"Obere Brisenmatt", "Untere Brisenmatt", "Brisenhüsli", "Hoh Brisen", "Eggen / Surenenpass",
	}
	if len(names) != len(want) {
		t.Fatalf("got %q\nwant %q", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("got %q\nwant %q", names, want)
		}
	}
	if got[3].Kind != "hut" || got[0].Detail != "Hauptgipfel, Isenthal (UR)" {
		t.Errorf("kinds and details: %+v, %+v", got[3], got[0])
	}

	// Without swisstopo, our places still come.
	s.Names = failingNames{}
	if got, err := s.Search(ctx, "sargans", near, "de"); err != nil || len(got) != 1 || got[0].Name != "Sargans" {
		t.Errorf("without swisstopo: %+v, %v", got, err)
	}

	// Our stop named just so comes before the nearer stops named after it.
	for i, name := range []string{"Zermatt, Spiss", "Zermatt Gant", "Zermatt Tuftern", "Zermatt Tufterchumme", "Zermatt, Bahnhofplatz", "Zermatt, Kirchbrücke"} {
		if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
			VALUES ('pt_stop', $1, 'didok', $1, ST_SetSRID(ST_MakePoint($2, 46.02), 4326))`, name, 7.75+float64(i)*0.001); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('pt_stop', 'Zermatt', 'didok', 'Zermatt', ST_SetSRID(ST_MakePoint(7.7478, 46.0240), 4326))`); err != nil {
		t.Fatal(err)
	}
	s.Names = nil
	if got, err = s.Search(ctx, "Zermatt", [2]float64{7.75, 46.02}, "de"); err != nil || len(got) == 0 || got[0].Name != "Zermatt" {
		t.Errorf("zermatt: %+v, %v", got, err)
	}

	// With a house number, the address before the stops on that street.
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('pt_stop', 'Beckenried, Seestrasse', 'didok', 'b1', ST_SetSRID(ST_MakePoint(8.48, 46.97), 4326))`); err != nil {
		t.Fatal(err)
	}
	s.Names = &GeoAdmin{URL: srv.URL}
	got, err = s.Search(ctx, "Seestrasse 1 Beckenried", near, "de")
	if err != nil || len(got) != 3 || got[0].Kind != "address" || got[2].Name != "Beckenried, Seestrasse" {
		t.Errorf("address: %+v, %v", got, err)
	}

	// The pass is not the inn named after it, 10 m away; a building of the
	// same name as the inn is.
	if _, err := pool.Exec(ctx, `INSERT INTO places (kind, name, source, source_id, geom)
		VALUES ('hotel', 'Berggasthaus Hospiz Sustenpass', 'osm', 'n1', ST_SetSRID(ST_MakePoint(8.4491, 46.7286), 4326))`); err != nil {
		t.Fatal(err)
	}
	s.Names = fixedNames{
		{Name: "Sustenpass", Kind: "name", Detail: "Pass, Innertkirchen (BE)", At: [2]float64{8.4491, 46.7287}},
		{Name: "Berggasthaus Hospiz Sustenpass", Kind: "name", At: [2]float64{8.4491, 46.7286}},
	}
	got, err = s.Search(ctx, "Sustenpass", near, "de")
	if err != nil || len(got) != 2 || got[0].Name != "Sustenpass" || got[1].Kind != "hotel" {
		t.Errorf("sustenpass: %+v, %v", got, err)
	}
}

// fixedNames answers every search with the same names.
type fixedNames []Found

func (f fixedNames) Search(context.Context, string, string) ([]Found, error) { return f, nil }
