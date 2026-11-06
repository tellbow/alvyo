package routing

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"

	"github.com/tellbow/alvyo/swiss/geo"
)

// Cells of the round trip's areas, about 230 × 220 m: finer than a path's
// width matters, coarse enough for a few thousand per area.
const (
	cellLon = 0.003
	cellLat = 0.002
)

// The outline around the cells, in metres (LV95): gaps narrower than
// twice closeM between paths are closed, holes smaller than minHoleM2 (the
// land between paths) filled, larger ones such as a pathless massif kept,
// lakes cut out (shrunk by shoreM, so the paths along a shore stay in), and
// the cells' steps smoothed to about simplifyM.
const (
	closeM    = 500
	minHoleM2 = 5_000_000
	shoreM    = 100
	simplifyM = 60
)

// overreach: the trees search this much beyond the longest time, so the
// paths that cross a limit are known up to their next node (GraphHopper's
// isochrones add 14 %).
const overreach = 1.15

// sptEdge is an edge leaving a node GraphHopper's shortest path tree
// reaches: its way from node from to node to ([lon, lat]), and the time at to
// by it (or from to, flowing back), in ms. The start's edge comes from -1 and
// is its point alone.
type sptEdge struct {
	from, to int64
	ms       float64
	way      [][2]float64
}

// nodeTimes returns each node's time: the least by any edge to it.
func nodeTimes(edges []sptEdge) map[int64]float64 {
	times := make(map[int64]float64, len(edges))
	for _, e := range edges {
		if t, ok := times[e.to]; !ok || e.ms < t {
			times[e.to] = e.ms
		}
	}
	return times
}

// spt asks GraphHopper for its shortest path tree from p within seconds
// (reverse: the times to p instead), as the edges leaving the nodes it
// reaches, with their ways: our endpoint (infra/graphhopper/src), as /spt
// gives only the tree's nodes, and straight lines between them cut across
// the slopes where paths wind, and miss the paths the tree does not take.
func (g *GraphHopper) spt(ctx context.Context, p geo.Point, profile string, seconds float64, reverse bool) ([]sptEdge, error) {
	q := url.Values{
		"point":        {fmt.Sprintf("%.6f,%.6f", p.Lat, p.Lon)},
		"profile":      {profile + "_time"},
		"time_limit":   {strconv.Itoa(int(math.Round(seconds)))},
		"reverse_flow": {strconv.FormatBool(reverse)},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSuffix(g.URL, "/")+"/reach-tree?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	// Tens of MB, but GraphHopper takes longer to gzip them than to send them.
	req.Header.Set("Accept-Encoding", "identity")
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: reachTimeout}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("routing: graphhopper: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		var r ghResponse
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		_ = json.Unmarshal(raw, &r)
		return nil, classifyError(resp.StatusCode, r)
	}
	rd := csv.NewReader(resp.Body)
	rd.ReuseRecord = true
	if _, err := rd.Read(); err != nil { // from_node,to_node,time,geometry
		return nil, fmt.Errorf("routing: spt: %w", err)
	}
	var edges []sptEdge
	for {
		rec, err := rd.Read()
		if errors.Is(err, io.EOF) {
			return edges, nil
		}
		if err != nil {
			return nil, fmt.Errorf("routing: spt: %w", err)
		}
		from, err1 := strconv.ParseInt(rec[0], 10, 64)
		to, err2 := strconv.ParseInt(rec[1], 10, 64)
		ms, err3 := strconv.ParseFloat(rec[2], 64)
		if err := errors.Join(err1, err2, err3); err != nil {
			return nil, fmt.Errorf("routing: spt: %w", err)
		}
		e := sptEdge{from: from, to: to, ms: ms}
		for pt := range strings.SplitSeq(rec[3], ";") {
			lon, lat, _ := strings.Cut(pt, " ")
			x, err1 := strconv.ParseFloat(lon, 64)
			y, err2 := strconv.ParseFloat(lat, 64)
			if err := errors.Join(err1, err2); err != nil {
				return nil, fmt.Errorf("routing: spt: %w", err)
			}
			e.way = append(e.way, [2]float64{x, y})
		}
		edges = append(edges, e)
	}
}

// Outliner draws the outline around grid cells (PostGIS).
type Outliner struct {
	DB *pgxpool.Pool
}

// Outline returns the largest area the cells (column, row of cellLon ×
// cellLat) make, closed, without lakes and smoothed (closeM): its rings,
// the outer one first. None for no cells.
func (o *Outliner) Outline(ctx context.Context, cells [][2]int) ([][][2]float64, error) {
	if len(cells) == 0 {
		return nil, nil
	}
	cols, rows := make([]int32, len(cells)), make([]int32, len(cells))
	for i, c := range cells {
		cols[i], rows[i] = int32(c[0]), int32(c[1])
	}
	var raw string
	err := o.DB.QueryRow(ctx, `
		WITH cell AS (SELECT unnest($1::int[]) AS i, unnest($2::int[]) AS j),
		size AS (SELECT $3::float8 AS w, $4::float8 AS h),
		cells AS (
			SELECT ST_Transform(ST_Union(ST_MakeEnvelope(i * w, j * h, (i + 1) * w, (j + 1) * h, 4326)), 2056) AS g
			FROM cell, size
		),
		part AS (SELECT (ST_Dump(ST_Buffer(ST_Buffer(g, $5::float8), -$5::float8))).geom AS g FROM cells),
		big AS (SELECT g FROM part ORDER BY ST_Area(g) DESC LIMIT 1),
		ring AS (SELECT r.path[1] AS n, ST_ExteriorRing(r.geom) AS l, ST_Area(r.geom) AS a FROM big, ST_DumpRings(big.g) r),
		filled AS (SELECT ST_MakePolygon(
			(SELECT l FROM ring WHERE n = 0),
			ARRAY(SELECT l FROM ring WHERE n > 0 AND a >= $6::float8 ORDER BY n)
		) AS g),
		-- after the holes are filled, so a small lake inside stays out too
		dry AS (
			SELECT (ST_Dump(ST_Difference(f.g, coalesce(
				(SELECT ST_Union(ST_Buffer(l.geom, -$8::float8)) FROM lakes l WHERE l.geom && f.g),
				ST_GeomFromText('POLYGON EMPTY', 2056))))).geom AS g
			FROM filled f
		)
		SELECT ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(g, $7::float8), 4326), 5)
		FROM dry ORDER BY ST_Area(g) DESC LIMIT 1`,
		cols, rows, cellLon, cellLat, closeM, minHoleM2, simplifyM, shoreM).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) { // all of it a lake
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("routing: outline: %w", err)
	}
	var poly struct {
		Coordinates [][][2]float64 `json:"coordinates"`
	}
	if err := json.Unmarshal([]byte(raw), &poly); err != nil {
		return nil, fmt.Errorf("routing: outline: %w", err)
	}
	return poly.Coordinates, nil
}

// segmentCells adds the cells a straight segment passes, in steps of half
// a cell.
func segmentCells(cells map[[2]int]bool, lon0, lat0, lon1, lat1 float64) {
	steps := int(math.Max(math.Abs(lon1-lon0)/cellLon, math.Abs(lat1-lat0)/cellLat)*2) + 1
	for s := 0; s <= steps; s++ {
		f := float64(s) / float64(steps)
		lon, lat := lon0+(lon1-lon0)*f, lat0+(lat1-lat0)*f
		cells[[2]int{int(math.Floor(lon / cellLon)), int(math.Floor(lat / cellLat))}] = true
	}
}

// wayCells adds the cells along the first fraction f (0 to 1) of a way, by
// its length.
func wayCells(cells map[[2]int]bool, way [][2]float64, f float64) {
	if len(way) == 0 {
		return
	}
	if len(way) == 1 {
		segmentCells(cells, way[0][0], way[0][1], way[0][0], way[0][1])
		return
	}
	k := math.Cos(way[0][1] * math.Pi / 180) // a degree of longitude in degrees of latitude
	length := func(a, b [2]float64) float64 { return math.Hypot((b[0]-a[0])*k, b[1]-a[1]) }
	total := 0.0
	for i := 1; i < len(way); i++ {
		total += length(way[i-1], way[i])
	}
	left := f * total
	for i := 1; i < len(way); i++ {
		a, b := way[i-1], way[i]
		d := length(a, b)
		if d > left {
			g := left / d
			segmentCells(cells, a[0], a[1], a[0]+(b[0]-a[0])*g, a[1]+(b[1]-a[1])*g)
			return
		}
		left -= d
		segmentCells(cells, a[0], a[1], b[0], b[1])
	}
}

// ReachBack returns the areas from which one is back at p within ReachHours
// at pace: out and back timed each in its own direction (uphill is slower
// than down), the smallest first. GraphHopper's shortest path trees give
// every node's time from p and to p; the paths to the nodes whose sum
// fits are rasterised, and their cells outlined.
func (r *Router) ReachBack(ctx context.Context, p geo.Point, profile string, pace float64) ([]ReachArea, error) {
	if pace <= 0 {
		pace = 1
	}
	most := float64(ReachHours[len(ReachHours)-1]) * 3600 / pace
	var out, back []sptEdge
	grp, gctx := errgroup.WithContext(ctx)
	grp.Go(func() (err error) {
		out, err = r.GraphHopper.spt(gctx, p, profile, most*overreach, false)
		return err
	})
	grp.Go(func() (err error) {
		back, err = r.GraphHopper.spt(gctx, p, profile, most*overreach, true)
		return err
	})
	if err := grp.Wait(); err != nil {
		return nil, err
	}
	backTimes := nodeTimes(back)
	return r.areas(ctx, pace, out, func(node int64, ms float64) float64 {
		if b, ok := backTimes[node]; ok {
			return ms + b
		}
		return math.Inf(1)
	})
}

// areas outlines, for each of ReachHours at pace, the edges as far as
// they get within it, the smallest first. ms gives the time at a node from
// its time on the way out.
func (r *Router) areas(ctx context.Context, pace float64, edges []sptEdge, ms func(node int64, out float64) float64) ([]ReachArea, error) {
	times := nodeTimes(edges)
	var areas []ReachArea
	for _, h := range ReachHours {
		limit := float64(h) * 3600 * 1000 / pace
		cells := map[[2]int]bool{}
		for _, e := range edges {
			t := ms(e.to, e.ms)
			if t <= limit {
				wayCells(cells, e.way, 1)
				continue
			}
			// As far as it gets from e.from: between junctions in the
			// mountains, that can be a kilometre or more. Its other end, if
			// reached, has its own edge back.
			if t0, ok := times[e.from]; ok {
				if t0 = ms(e.from, t0); t0 < limit {
					wayCells(cells, e.way, (limit-t0)/(t-t0))
				}
			}
		}
		list := make([][2]int, 0, len(cells))
		for c := range cells {
			list = append(list, c)
		}
		outline, err := r.Outlines.Outline(ctx, list)
		if err != nil {
			return nil, err
		}
		if len(outline) > 0 {
			areas = append(areas, ReachArea{Hours: h, Outline: outline})
		}
	}
	return areas, nil
}
