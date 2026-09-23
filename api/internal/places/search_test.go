package places

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/tellbow/odysgeh/api/internal/testdb"
)

func TestParseLabel(t *testing.T) {
	for _, c := range []struct{ label, name, detail string }{
		{"<i>Hauptgipfel</i> <b>Brisen</b> (UR) - Isenthal", "Brisen", "Hauptgipfel, Isenthal (UR)"},
		{"<b>Gitsch</b> (BE) - Lauterbrunnen", "Gitsch", "Lauterbrunnen (BE)"},
		{"<i>Pass</i> <b>Eggen|Surenenpass</b> (UR) - Attinghausen", "Eggen / Surenenpass", "Pass, Attinghausen (UR)"},
		{"<i>Ort</i> <b>Büsingen am Hochrhein</b> () - Büsingen am Hochrhein", "Büsingen am Hochrhein", "Ort, Büsingen am Hochrhein"},
		{"Seestrasse 1 <b>6375 Beckenried</b>", "Seestrasse 1, 6375 Beckenried", ""},
		{"<b>Caf&eacute; <script>x</script></b>", "Café x", ""},
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
	// Ours first: whole words first, then the nearer of two equal matches.
	// swisstopo's two "Brisenhaus" buildings repeat our hut, and its
	// "Brisenmatt" the stop there.
	want := []string{
		"Brisen, Bergstation", "Brisen, Talstation", "Brisenhaus", "Welschenrohr, Brisenmatt",
		"Brisen", "Obere Brisenmatt", "Untere Brisenmatt", "Brisenhüsli", "Hoh Brisen", "Eggen / Surenenpass",
	}
	if len(names) != len(want) {
		t.Fatalf("got %q\nwant %q", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("got %q\nwant %q", names, want)
		}
	}
	if got[2].Kind != "hut" || got[4].Detail != "Hauptgipfel, Isenthal (UR)" {
		t.Errorf("kinds and details: %+v, %+v", got[2], got[4])
	}

	// Without swisstopo, our places still come.
	s.Names = failingNames{}
	if got, err := s.Search(ctx, "sargans", near, "de"); err != nil || len(got) != 1 || got[0].Name != "Sargans" {
		t.Errorf("without swisstopo: %+v, %v", got, err)
	}
}
