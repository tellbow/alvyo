package places

import (
	"context"
	"fmt"
	"log/slog"
	"math"
	"strings"
)

// Found is a search result: one of our places, or a geographical name or
// address from swisstopo.
type Found struct {
	Name   string     `json:"name"`
	Detail string     `json:"detail" doc:"Stop modes, the OSM hut type, or the kind of name and its municipality"`
	Kind   string     `json:"kind" enum:"pt_stop,hut,hotel,campsite,name,address"`
	At     [2]float64 `json:"at" doc:"lon, lat"`
}

// Names searches geographical names; *GeoAdmin in production.
type Names interface {
	Search(ctx context.Context, text, lang string) ([]Found, error)
}

// Search limits.
const (
	searchOurs  = 6
	searchTotal = 12
	sameWithinM = 500 // one place found in both sources, or twice
)

// Search finds places by name: those named exactly so first (ours, then
// swisstopo's; for a text with a house number its addresses), then our stops, huts and accommodation (the nearest to near
// among equally good matches), then swisstopo's other names; without those
// that repeat a place already found. When swisstopo cannot be reached, only
// our places are returned.
func (s *Store) Search(ctx context.Context, text string, near [2]float64, lang string) ([]Found, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT kind, name, detail, ST_X(geom), ST_Y(geom) FROM places
		WHERE $1 <% name
		ORDER BY lower(name) = lower($1) DESC, word_similarity($1, name) DESC,
			geom <-> ST_SetSRID(ST_MakePoint($2, $3), 4326), length(name)
		LIMIT $4`, text, near[0], near[1], searchOurs)
	if err != nil {
		return nil, fmt.Errorf("places: search: %w", err)
	}
	defer rows.Close()
	var ours []Found
	for rows.Next() {
		var f Found
		if err := rows.Scan(&f.Kind, &f.Name, &f.Detail, &f.At[0], &f.At[1]); err != nil {
			return nil, err
		}
		ours = append(ours, f)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var names []Found
	if s.Names != nil {
		if names, err = s.Names.Search(ctx, text, lang); err != nil {
			slog.WarnContext(ctx, "place search without swisstopo names", "err", err)
			names = nil
		}
	}
	// With a house number, an address is what is meant.
	number := strings.ContainsAny(text, "0123456789")
	exact := func(f Found) bool {
		return strings.EqualFold(strings.TrimSpace(f.Name), strings.TrimSpace(text)) || (number && f.Kind == "address")
	}
	out := []Found{}
	add := func(list []Found, wanted bool, check bool) {
		for _, f := range list {
			if len(out) == searchTotal {
				return
			}
			if exact(f) != wanted || (check && repeats(out, f, exact(f))) {
				continue
			}
			out = append(out, f)
		}
	}
	add(ours, true, false)
	add(names, true, true)
	add(ours, false, false)
	add(names, false, true)
	return out, nil
}

// repeats reports whether f names a place already in found: one name
// contains the other and they are close. A name just as searched only
// repeats the same name: the pass is not the inn named after it.
func repeats(found []Found, f Found, exact bool) bool {
	name := strings.ToLower(f.Name)
	for _, o := range found {
		other := strings.ToLower(o.Name)
		same := name == other
		if !exact {
			same = strings.Contains(name, other) || strings.Contains(other, name)
		}
		if same && distanceM(o.At, f.At) < sameWithinM {
			return true
		}
	}
	return false
}

// distanceM is the distance between two lon, lat points, good enough for
// hundreds of metres.
func distanceM(a, b [2]float64) float64 {
	const mPerDeg = 111_320.0
	dx := (a[0] - b[0]) * mPerDeg * math.Cos((a[1]+b[1])/2*math.Pi/180)
	dy := (a[1] - b[1]) * mPerDeg
	return math.Hypot(dx, dy)
}
