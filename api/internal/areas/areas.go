// Package areas finds the protected areas a route crosses: wildlife rest
// areas (Wildruhezonen, the Swiss National Park among them) and federal
// hunting reserves (eidg. Jagdbanngebiete). The rest areas come from the
// cantons and are published by BAFU only as a map layer, so geo.admin's
// identify service is asked along the line; answers are cached.
package areas

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/swiss/geo"
)

// IdentifyURL is geo.admin's feature identify service.
const IdentifyURL = "https://api3.geo.admin.ch/rest/services/api/MapServer/identify"

// The layers asked for.
const (
	restLayer    = "ch.bafu.wrz-wildruhezonen_portal"
	reserveLayer = "ch.bafu.bundesinventare-jagdbanngebiete"
)

const (
	// simplifyM keeps requests short; an area is missed only where the line
	// grazes its edge by less than this.
	simplifyM = 5
	// chunkPoints per request, for the URL to stay short.
	chunkPoints = 200
	// cacheFor: areas change a few times a year.
	cacheFor = 30 * 24 * time.Hour
)

// ErrUnavailable means geo.admin did not answer usefully.
var ErrUnavailable = errors.New("areas: geo.admin unavailable")

// Texts is a text in the national languages (and English where given).
type Texts struct {
	De string `json:"de"`
	Fr string `json:"fr"`
	It string `json:"it"`
	En string `json:"en,omitempty"`
}

// Period is when an area's rules apply, as month and day, both included;
// from after to wraps over the new year (1 December to 20 April).
type Period struct {
	From string `json:"from" doc:"MM-DD"`
	To   string `json:"to" doc:"MM-DD"`
}

// Contains reports whether the day of t is in the period.
func (p Period) Contains(t time.Time) bool {
	d := t.Format("01-02")
	if p.From <= p.To {
		return d >= p.From && d <= p.To
	}
	return d >= p.From || d <= p.To
}

// Area is a protected area a line crosses.
type Area struct {
	Kind    string `json:"kind" enum:"wildlife_rest,hunting_reserve"`
	ID      string `json:"id" doc:"The layer's feature id"`
	Name    string `json:"name"`
	Binding bool   `json:"binding" doc:"Legally binding; otherwise a recommendation"`
	Rule    Texts  `json:"rule" doc:"e.g. no entry, or keep to the paths"`
	Note    string `json:"note,omitempty" doc:"More about the rules (German)"`
	// Period is when the rules apply; nil when always.
	Period *Period `json:"period,omitempty"`
	Link   string  `json:"link,omitempty" doc:"The canton's or BAFU's page on it"`
	// Stages are the numbers (from 1) of the journey stages crossing it.
	Stages []int `json:"stages,omitempty"`
	// Where are the parts of the line in it, [lon, lat]: where the map goes
	// on a tap.
	Where [][][2]float64 `json:"where,omitempty"`
}

// Finder asks geo.admin and caches its answers.
type Finder struct {
	DB        *pgxpool.Pool
	URL       string       // defaults to IdentifyURL
	Client    *http.Client // defaults to a 10 s timeout
	UserAgent string
}

// Prune deletes answers older than cacheFor: every line drawn in the
// planner leaves one.
func (f *Finder) Prune(ctx context.Context) error {
	_, err := f.DB.Exec(ctx, `DELETE FROM area_cache WHERE fetched_at < now() - make_interval(secs => $1)`, cacheFor.Seconds())
	return err
}

// PruneEvery runs Prune until ctx ends.
func (f *Finder) PruneEvery(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		if err := f.Prune(ctx); err != nil && ctx.Err() == nil {
			slog.ErrorContext(ctx, "area cache prune", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// Crossed returns the areas line crosses, rest areas first, by name.
func (f *Finder) Crossed(ctx context.Context, line []geo.Point) ([]Area, error) {
	pts := geo.Simplify(line, simplifyM)
	if len(pts) < 2 {
		return []Area{}, nil
	}
	key := "where:" + lineKey(pts) // answers from before Where are not used
	var cached []byte
	err := f.DB.QueryRow(ctx, `SELECT areas FROM area_cache WHERE line_key = $1 AND fetched_at > now() - make_interval(secs => $2)`,
		key, cacheFor.Seconds()).Scan(&cached)
	if err == nil {
		var out []Area
		if err := json.Unmarshal(cached, &out); err == nil {
			return out, nil
		}
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("areas: cache: %w", err)
	}

	found := map[string]Area{}
	// Consecutive chunks share a point, so that no segment is left out.
	for start := 0; start < len(pts)-1; start += chunkPoints - 1 {
		chunk := pts[start:min(start+chunkPoints, len(pts))]
		areas, err := f.identify(ctx, chunk)
		if err != nil {
			return nil, err
		}
		for _, a := range areas {
			if _, seen := found[a.Kind+"/"+a.ID]; !seen {
				a.Where = where(pts, a.geometry) // on the whole line: an area can span chunks
				found[a.Kind+"/"+a.ID] = a.Area
			}
		}
	}
	out := make([]Area, 0, len(found))
	for _, a := range found {
		out = append(out, a)
	}
	slices.SortFunc(out, func(a, b Area) int {
		if a.Kind != b.Kind {
			return strings.Compare(b.Kind, a.Kind) // wildlife_rest first
		}
		return strings.Compare(a.Name, b.Name)
	})
	if b, err := json.Marshal(out); err == nil {
		_, _ = f.DB.Exec(ctx, `INSERT INTO area_cache (line_key, areas) VALUES ($1, $2)
			ON CONFLICT (line_key) DO UPDATE SET areas = excluded.areas, fetched_at = now()`, key, b)
	}
	return out, nil
}

func lineKey(pts []geo.Point) string {
	h := sha256.New()
	for _, p := range pts {
		_, _ = fmt.Fprintf(h, "%.5f,%.5f;", p.Lon, p.Lat) // a hash never fails
	}
	return hex.EncodeToString(h.Sum(nil))
}

type identifyResponse struct {
	Results []identifyResult `json:"results"`
}

type identifyResult struct {
	LayerBodID string         `json:"layerBodId"`
	FeatureID  json.Number    `json:"featureId"`
	Attributes map[string]any `json:"attributes"`
	// With geometries (as GeoJSON) the attributes come as properties.
	Properties map[string]any  `json:"properties"`
	Geometry   json.RawMessage `json:"geometry"`
}

// shaped is an area with its shape (GeoJSON).
type shaped struct {
	Area
	geometry json.RawMessage
}

func (f *Finder) identify(ctx context.Context, pts []geo.Point) ([]shaped, error) {
	r, err := f.ask(ctx, pts, []string{restLayer, reserveLayer}, true)
	if err != nil {
		return nil, err
	}
	var out []shaped
	for _, res := range r.Results {
		s := func(k string) string {
			v, _ := res.Attributes[k].(string)
			return strings.TrimSpace(v)
		}
		switch res.LayerBodID {
		case restLayer:
			if s("wrz_name") == "" {
				continue // an allowed path through a zone, not the zone
			}
			out = append(out, shaped{Area{
				Kind: "wildlife_rest", ID: res.FeatureID.String(), Name: s("wrz_name"),
				Binding: s("schutzs_de") == "rechtsverbindlich",
				Rule:    Texts{De: s("best_de"), Fr: s("best_fr"), It: s("best_it")},
				Note:    s("zusatzinformation"),
				Period:  parsePeriod(s("schutzzeit")),
				Link:    s("url_kanton"),
			}, res.Geometry})
		case reserveLayer:
			out = append(out, shaped{Area{
				Kind: "hunting_reserve", ID: res.FeatureID.String(), Name: s("gebietsname"), Binding: true,
				Rule: Texts{De: s("typ_de"), Fr: s("typ_fr"), It: s("typ_it"), En: s("typ_en")},
				Link: s("refobjblatt"),
			}, res.Geometry})
		}
	}
	return out, nil
}

// ask asks geo.admin for the features of layers along pts, with their
// geometries if geometry.
func (f *Finder) ask(ctx context.Context, pts []geo.Point, layers []string, geometry bool) (identifyResponse, error) {
	path := make([][2]float64, len(pts))
	west, south, east, north := pts[0].Lon, pts[0].Lat, pts[0].Lon, pts[0].Lat
	for i, p := range pts {
		path[i] = [2]float64{round5(p.Lon), round5(p.Lat)}
		west, east = min(west, p.Lon), max(east, p.Lon)
		south, north = min(south, p.Lat), max(north, p.Lat)
	}
	geom, _ := json.Marshal(map[string]any{"paths": [][][2]float64{path}, "spatialReference": map[string]int{"wkid": 4326}})
	q := url.Values{
		"geometryType":   {"esriGeometryPolyline"},
		"geometry":       {string(geom)},
		"layers":         {"all:" + strings.Join(layers, ",")},
		"sr":             {"4326"},
		"tolerance":      {"0"},
		"returnGeometry": {strconv.FormatBool(geometry)},
		"lang":           {"de"},
		// Needed by the service; with tolerance 0 they change nothing.
		"mapExtent":    {fmt.Sprintf("%f,%f,%f,%f", west, south, east, north)},
		"imageDisplay": {"1000,1000,96"},
	}
	if geometry {
		q.Set("geometryFormat", "geojson")
	}
	base := f.URL
	if base == "" {
		base = IdentifyURL
	}
	var r identifyResponse
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"?"+q.Encode(), nil)
	if err != nil {
		return r, err
	}
	if f.UserAgent != "" {
		req.Header.Set("User-Agent", f.UserAgent)
	}
	client := f.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return r, fmt.Errorf("%w: %w", ErrUnavailable, err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil || resp.StatusCode != http.StatusOK {
		return r, fmt.Errorf("%w: status %d", ErrUnavailable, resp.StatusCode)
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if err := d.Decode(&r); err != nil {
		return r, fmt.Errorf("%w: %w", ErrUnavailable, err)
	}
	for i, res := range r.Results {
		if res.Attributes == nil {
			r.Results[i].Attributes = res.Properties
		}
	}
	return r, nil
}

// round5 keeps about a metre.
func round5(x float64) float64 { return math.Round(x*1e5) / 1e5 }

// parsePeriod reads "01.12. - 20.04."; nil for the whole year or anything
// else.
func parsePeriod(s string) *Period {
	parts := strings.Split(s, "-")
	if len(parts) != 2 {
		return nil
	}
	day := func(v string) (string, bool) {
		f := strings.FieldsFunc(v, func(r rune) bool { return r == '.' || r == ' ' })
		if len(f) != 2 {
			return "", false
		}
		d, err1 := strconv.Atoi(f[0])
		m, err2 := strconv.Atoi(f[1])
		if err1 != nil || err2 != nil || d < 1 || d > 31 || m < 1 || m > 12 {
			return "", false
		}
		return fmt.Sprintf("%02d-%02d", m, d), true
	}
	from, ok1 := day(parts[0])
	to, ok2 := day(parts[1])
	if !ok1 || !ok2 || (from == "01-01" && to == "12-31") {
		return nil
	}
	return &Period{From: from, To: to}
}
