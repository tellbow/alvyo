package areas

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/tellbow/alvyo/swiss/geo"
)

// The layers of current notices: closed hiking trails (ASTRA, from the
// cantons' trail organisations) and the army's published shooting.
const (
	closureLayer  = "ch.astra.wanderland-sperrungen_umleitungen"
	shootingLayer = "ch.vbs.schiessanzeigen"
)

const (
	// noticesFor: closures and shooting days change daily.
	noticesFor = time.Hour
	// alongM: a closed path counts when the line runs along it this far,
	// not where it only crosses it; nearM is how close counts as on it.
	alongM = 50
	nearM  = 20
)

// Notice is a current closure or shooting on a line's way.
type Notice struct {
	Kind   string `json:"kind" enum:"closure,shooting"`
	ID     string `json:"id" doc:"The layer's feature id"`
	Title  Texts  `json:"title"`
	Reason *Texts `json:"reason,omitempty" doc:"Closures: why"`
	// Closures: the days it is closed, both included.
	From string `json:"from,omitempty" format:"date"`
	To   string `json:"to,omitempty" format:"date"`
	// Shooting: the days announced, with the hours when known.
	Days  []ShootingDay `json:"days,omitempty"`
	Phone string        `json:"phone,omitempty" doc:"Shooting: where to ask"`
	Link  *Texts        `json:"link,omitempty" doc:"The army's page on the shooting"`
	// Stages are the numbers (from 1) of the journey stages concerned.
	Stages []int `json:"stages,omitempty"`
	// Where are the parts of the line concerned, [lon, lat]: where the map
	// goes on a tap.
	Where [][][2]float64 `json:"where,omitempty"`
}

// ShootingDay is a day with shooting, the hours as «0800» and «1700»,
// empty when not given (then all day).
type ShootingDay struct {
	Date string `json:"date" format:"date"`
	From string `json:"from,omitempty"`
	To   string `json:"to,omitempty"`
}

// Notices returns the closures the line runs along and the shooting areas
// it crosses, from today on; closures first.
func (f *Finder) Notices(ctx context.Context, line []geo.Point, today time.Time) ([]Notice, error) {
	pts := geo.Simplify(line, simplifyM)
	if len(pts) < 2 {
		return []Notice{}, nil
	}
	key := "notices-where:" + lineKey(pts) // answers from before Where are not used
	var cached []byte
	err := f.DB.QueryRow(ctx, `SELECT areas FROM area_cache WHERE line_key = $1 AND fetched_at > now() - make_interval(secs => $2)`,
		key, noticesFor.Seconds()).Scan(&cached)
	var all []Notice
	switch {
	case err == nil && json.Unmarshal(cached, &all) == nil:
	case err != nil && !errors.Is(err, pgx.ErrNoRows):
		return nil, fmt.Errorf("areas: cache: %w", err)
	default:
		if all, err = f.fetchNotices(ctx, pts); err != nil {
			return nil, err
		}
		if b, err := json.Marshal(all); err == nil {
			_, _ = f.DB.Exec(ctx, `INSERT INTO area_cache (line_key, areas) VALUES ($1, $2)
				ON CONFLICT (line_key) DO UPDATE SET areas = excluded.areas, fetched_at = now()`, key, b)
		}
	}
	return current(all, today.Format(time.DateOnly)), nil
}

// current keeps what is not over by day.
func current(all []Notice, day string) []Notice {
	out := []Notice{}
	for _, n := range all {
		if n.Kind == "shooting" {
			n.Days = slices.DeleteFunc(slices.Clone(n.Days), func(d ShootingDay) bool { return d.Date < day })
			if len(n.Days) == 0 {
				continue
			}
		} else if n.To != "" && n.To < day {
			continue
		}
		out = append(out, n)
	}
	return out
}

func (f *Finder) fetchNotices(ctx context.Context, pts []geo.Point) ([]Notice, error) {
	found := map[string]Notice{}
	var order []string
	for start := 0; start < len(pts)-1; start += chunkPoints - 1 {
		chunk := pts[start:min(start+chunkPoints, len(pts))]
		r, err := f.ask(ctx, chunk, []string{closureLayer, shootingLayer}, true)
		if err != nil {
			return nil, err
		}
		for _, res := range r.Results {
			n, ok := notice(res, pts)
			key := n.Kind + "/" + n.ID
			if _, seen := found[key]; ok && !seen {
				n.Where = where(pts, res.Geometry)
				found[key] = n
				order = append(order, key)
			}
		}
	}
	out := make([]Notice, 0, len(order))
	for _, k := range order {
		out = append(out, found[k])
	}
	slices.SortStableFunc(out, func(a, b Notice) int { return strings.Compare(a.Kind, b.Kind) }) // closures first
	return out, nil
}

// notice reads an identify result; false for detours (the way round a
// closure), closures the line only crosses, and what cannot be read.
func notice(res identifyResult, line []geo.Point) (Notice, bool) {
	s := func(k string) string {
		v, _ := res.Attributes[k].(string)
		return strings.TrimSpace(v)
	}
	texts := func(k string) Texts {
		return Texts{De: s(k + "_de"), Fr: s(k + "_fr"), It: s(k + "_it"), En: s(k + "_en")}
	}
	list := func(k string) []string {
		var out []string
		if vs, ok := res.Attributes[k].([]any); ok {
			for _, v := range vs {
				str, _ := v.(string)
				out = append(out, strings.TrimSpace(str))
			}
		}
		return out
	}
	id := res.FeatureID.String()
	switch res.LayerBodID {
	case closureLayer:
		if s("sperrungen_type") != "closed_way" || !runsAlong(line, res.Geometry) {
			return Notice{}, false
		}
		n := Notice{Kind: "closure", ID: id, Title: texts("title")}
		if r := texts("reason"); r.De != "" {
			n.Reason = &r
		}
		// «09.06.2026 – 31.03.2027»
		if from, to, ok := strings.Cut(s("duration_de"), "–"); ok {
			n.From, n.To = isoDate(from), isoDate(to)
		}
		return n, true
	case shootingLayer:
		n := Notice{Kind: "shooting", ID: id, Title: Texts{De: s("bezeichnung")}, Phone: s("infotelefonnr")}
		link := texts("url")
		if link.De != "" {
			n.Link = &link
		}
		dates, from, to := list("belegungsdatum"), list("zeit_von"), list("zeit_bis")
		for i, d := range dates {
			day := ShootingDay{Date: isoDate(d)}
			if i < len(from) && i < len(to) {
				day.From, day.To = from[i], to[i]
			}
			if day.Date != "" {
				n.Days = append(n.Days, day)
			}
		}
		return n, len(n.Days) > 0
	}
	return Notice{}, false
}

// isoDate turns «31.03.2027» into «2027-03-31»; empty if it is none.
func isoDate(s string) string {
	t, err := time.Parse("02.01.2006", strings.TrimSpace(s))
	if err != nil {
		return ""
	}
	return t.Format(time.DateOnly)
}

// runsAlong reports whether line runs at least alongM along the GeoJSON
// line or lines g (within nearM).
func runsAlong(line []geo.Point, g json.RawMessage) bool {
	var geom struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
	}
	if json.Unmarshal(g, &geom) != nil {
		return false
	}
	var parts [][][2]float64
	switch geom.Type {
	case "LineString":
		var l [][2]float64
		if json.Unmarshal(geom.Coordinates, &l) != nil {
			return false
		}
		parts = [][][2]float64{l}
	case "MultiLineString":
		if json.Unmarshal(geom.Coordinates, &parts) != nil {
			return false
		}
	default:
		return false
	}
	near := func(p geo.Point) bool {
		for _, part := range parts {
			for i := 1; i < len(part); i++ {
				if segmentDistance(p, part[i-1], part[i]) <= nearM {
					return true
				}
			}
		}
		return false
	}
	dense, _ := geo.Densify(line, nearM/2)
	along := 0.0
	for i := 1; i < len(dense); i++ {
		if near(dense[i-1]) && near(dense[i]) {
			along += geo.Distance(dense[i-1], dense[i])
		}
	}
	return along >= alongM
}

// segmentDistance is how far p is from the segment a–b, in metres (flat
// at this scale).
func segmentDistance(p geo.Point, a, b [2]float64) float64 {
	const mPerDeg = 111_320.0
	kx := mPerDeg * math.Cos(p.Lat*math.Pi/180)
	px, py := p.Lon*kx, p.Lat*mPerDeg
	ax, ay, bx, by := a[0]*kx, a[1]*mPerDeg, b[0]*kx, b[1]*mPerDeg
	dx, dy := bx-ax, by-ay
	t := 0.0
	if l := dx*dx + dy*dy; l > 0 {
		t = math.Max(0, math.Min(1, ((px-ax)*dx+(py-ay)*dy)/l))
	}
	return math.Hypot(px-(ax+t*dx), py-(ay+t*dy))
}
