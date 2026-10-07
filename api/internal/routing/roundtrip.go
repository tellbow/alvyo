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
// land between paths) filled, larger ones such as lakes kept, and the cells'
// steps smoothed to about simplifyM.
const (
	closeM    = 300
	minHoleM2 = 1_000_000
	simplifyM = 60
)

// sptNode is a node of GraphHopper's shortest path tree: where it is, the
// node before it and the time to it (or from it, flowing back), in ms.
type sptNode struct {
	lon, lat, prevLon, prevLat float64
	ms                         float64
}

// spt asks GraphHopper for its shortest path tree from p within seconds
// (reverse: the times to p instead).
func (g *GraphHopper) spt(ctx context.Context, p geo.Point, profile string, seconds float64, reverse bool) (map[int64]sptNode, error) {
	q := url.Values{
		"point":        {fmt.Sprintf("%.6f,%.6f", p.Lat, p.Lon)},
		"profile":      {profile + "_time"},
		"time_limit":   {strconv.Itoa(int(math.Round(seconds)))},
		"reverse_flow": {strconv.FormatBool(reverse)},
		"columns":      {"node_id,prev_longitude,prev_latitude,longitude,latitude,time"},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSuffix(g.URL, "/")+"/spt?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
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
	if _, err := rd.Read(); err != nil { // the header, in the columns' order
		return nil, fmt.Errorf("routing: spt: %w", err)
	}
	nodes := map[int64]sptNode{}
	for {
		rec, err := rd.Read()
		if errors.Is(err, io.EOF) {
			return nodes, nil
		}
		if err != nil {
			return nil, fmt.Errorf("routing: spt: %w", err)
		}
		var v [6]float64
		// The start has no node before it: «null» there.
		start := rec[1] == "null" || rec[1] == ""
		for i := range v {
			if start && (i == 1 || i == 2) {
				continue
			}
			if v[i], err = strconv.ParseFloat(rec[i], 64); err != nil {
				return nil, fmt.Errorf("routing: spt: %w", err)
			}
		}
		n := sptNode{prevLon: v[1], prevLat: v[2], lon: v[3], lat: v[4], ms: v[5]}
		if start {
			n.prevLon, n.prevLat = n.lon, n.lat
		}
		nodes[int64(v[0])] = n
	}
}

// Outliner draws the outline around grid cells (PostGIS).
type Outliner struct {
	DB *pgxpool.Pool
}

// Outline returns the largest area the cells (column, row of cellLon ×
// cellLat) make, closed and smoothed (closeM): its rings, the outer one
// first. None for no cells.
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
		ring AS (SELECT r.path[1] AS n, ST_ExteriorRing(r.geom) AS l, ST_Area(r.geom) AS a FROM big, ST_DumpRings(big.g) r)
		SELECT ST_AsGeoJSON(ST_Transform(ST_SimplifyPreserveTopology(ST_MakePolygon(
			(SELECT l FROM ring WHERE n = 0),
			ARRAY(SELECT l FROM ring WHERE n > 0 AND a >= $6::float8 ORDER BY n)
		), $7::float8), 4326), 5)`,
		cols, rows, cellLon, cellLat, closeM, minHoleM2, simplifyM).Scan(&raw)
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
	var out, back map[int64]sptNode
	grp, gctx := errgroup.WithContext(ctx)
	grp.Go(func() (err error) {
		out, err = r.GraphHopper.spt(gctx, p, profile, most, false)
		return err
	})
	grp.Go(func() (err error) {
		back, err = r.GraphHopper.spt(gctx, p, profile, most, true)
		return err
	})
	if err := grp.Wait(); err != nil {
		return nil, err
	}
	var areas []ReachArea
	for _, h := range ReachHours {
		limit := float64(h) * 3600 * 1000 / pace
		cells := map[[2]int]bool{}
		for id, n := range out {
			if b, ok := back[id]; ok && n.ms+b.ms <= limit {
				segmentCells(cells, n.prevLon, n.prevLat, n.lon, n.lat)
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
