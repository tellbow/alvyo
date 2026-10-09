// Package official keeps the official hiking routes of Wanderland Schweiz
// (ASTRA / SchweizMobil) as public routes and journeys of the account
// «wanderland»: infra/data-import/import-wanderland.sh loads them into
// wanderland_routes and wanderland_stages, a sync makes Alvyo items of them.
package official

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/swiss/geo"
)

// Username is the account that owns the official routes.
const Username = "wanderland"

// minRoutes guards against a broken import deleting every official route:
// Wanderland has about 440. A variable for tests.
var minRoutes = 100

// lockKey is the advisory lock that keeps two API instances from syncing at
// once.
const lockKey = 0x0ff1c1a1

// Syncer makes Alvyo routes and journeys of the imported Wanderland data.
type Syncer struct {
	DB       *pgxpool.Pool
	Importer *imports.Importer
}

// Result counts what a sync did.
type Result struct {
	Created, Updated, Deleted, Unchanged, Failed int
}

// SyncEvery syncs whenever an import is newer than the last sync, checked
// at start and then every interval.
func (s *Syncer) SyncEvery(ctx context.Context, interval time.Duration) {
	for {
		if res, ran, err := s.Sync(ctx); err != nil && ctx.Err() == nil {
			slog.WarnContext(ctx, "official routes", "err", err)
		} else if ran {
			slog.InfoContext(ctx, "official routes synced", "created", res.Created, "updated", res.Updated,
				"deleted", res.Deleted, "unchanged", res.Unchanged, "failed", res.Failed)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// Sync brings the official routes up to the last import, if it is newer
// than the last sync; ran says whether it did. Routes that fail (e.g.
// geo.admin not answering) are left as they were and tried again at the
// next check.
func (s *Syncer) Sync(ctx context.Context) (res Result, ran bool, err error) {
	conn, err := s.DB.Acquire(ctx)
	if err != nil {
		return res, false, err
	}
	defer conn.Release()
	var locked bool
	if err := conn.QueryRow(ctx, `SELECT pg_try_advisory_lock($1)`, lockKey).Scan(&locked); err != nil || !locked {
		return res, false, err
	}
	defer func() { _, _ = conn.Exec(context.WithoutCancel(ctx), `SELECT pg_advisory_unlock($1)`, lockKey) }()

	var imported time.Time
	err = s.DB.QueryRow(ctx, `SELECT imported_at FROM wanderland_import
		WHERE synced_at IS NULL OR synced_at < imported_at`).Scan(&imported)
	if errors.Is(err, pgx.ErrNoRows) {
		return res, false, nil
	}
	if err != nil {
		return res, false, fmt.Errorf("official: import: %w", err)
	}
	res, err = s.sync(ctx)
	if err != nil {
		return res, true, err
	}
	if res.Failed == 0 {
		_, err = s.DB.Exec(ctx, `UPDATE wanderland_import SET synced_at = $1`, imported)
	}
	return res, true, err
}

// source is a Wanderland route as imported, its stages as the parts walked.
type source struct {
	Nr, Name, Kind string
	Parts          []part
}

// part is a stage, or what is walked of it when it rides a boat, a bus or a
// cable car on the way; such a stage becomes several Alvyo stages.
type part struct {
	Title    string
	Line     []geo.Point
	Transfer string // how one gets to it from the part before: "", "pt" or "cablecar"
}

// item is an official route as it is in Alvyo.
type item struct {
	routeID, journeyID *uuid.UUID
	hash               string
}

func (s *Syncer) sync(ctx context.Context) (Result, error) {
	var res Result
	var owner uuid.UUID
	if err := s.DB.QueryRow(ctx, `SELECT id FROM users WHERE username = $1`, Username).Scan(&owner); err != nil {
		return res, fmt.Errorf("official: owner: %w", err)
	}
	srcs, err := s.load(ctx)
	if err != nil {
		return res, err
	}
	if len(srcs) < minRoutes {
		return res, fmt.Errorf("official: only %d routes imported, at least %d expected", len(srcs), minRoutes)
	}
	have := map[string]item{}
	rows, err := s.DB.Query(ctx, `SELECT nr, route_id, journey_id, hash FROM official`)
	if err != nil {
		return res, err
	}
	for rows.Next() {
		var nr string
		var it item
		if err := rows.Scan(&nr, &it.routeID, &it.journeyID, &it.hash); err != nil {
			return res, err
		}
		have[nr] = it
	}
	if err := rows.Err(); err != nil {
		return res, err
	}

	seen := map[string]bool{}
	for _, src := range srcs {
		seen[src.Nr] = true
		old, exists := have[src.Nr]
		hash := src.hash()
		if exists && old.hash == hash {
			res.Unchanged++
			continue
		}
		if err := s.put(ctx, owner, src, hash, old, exists); err != nil {
			if ctx.Err() != nil {
				return res, ctx.Err()
			}
			slog.WarnContext(ctx, "official route", "nr", src.Nr, "err", err)
			res.Failed++
			continue
		}
		if exists {
			res.Updated++
		} else {
			res.Created++
		}
	}
	for nr, it := range have {
		if seen[nr] {
			continue
		}
		if err := s.remove(ctx, it); err != nil {
			return res, err
		}
		res.Deleted++
	}
	return res, nil
}

// load reads the imported routes that have stages, each stage joined to one
// line, turned to follow the one before and cut where it rides.
func (s *Syncer) load(ctx context.Context) ([]source, error) {
	// A stage rides where it runs more than 100 m along a piece of transport;
	// what is left within 5 m of it is not walked.
	rows, err := s.DB.Query(ctx, `
		SELECT r.nr, r.name, r.kind,
			array_agg(trim(st.start_name || ' – ' || st.end_name, ' –') ORDER BY st.stage),
			array_agg(ST_AsGeoJSON(ST_LineMerge(coalesce(ride.walk, st.geom)), 6) ORDER BY st.stage),
			array_agg(coalesce(ride.mode, '') ORDER BY st.stage)
		FROM wanderland_routes r
		JOIN wanderland_stages st ON st.nr = r.nr
		LEFT JOIN LATERAL (
			SELECT ST_Difference(st.geom, ST_Union(t.zone)) AS walk,
				CASE WHEN bool_or(t.mode = 'Luftseilbahn') THEN 'cablecar' ELSE 'pt' END AS mode
			FROM (SELECT mode, ST_Buffer(geom::geography, 5)::geometry AS zone FROM wanderland_transport) t
			WHERE ST_Intersects(st.geom, t.zone) AND ST_Length(ST_Intersection(st.geom, t.zone)::geography) > 100
			HAVING count(*) > 0
		) ride ON true
		WHERE r.kind IN ('national', 'regional', 'local', 'handicap')
		GROUP BY r.nr ORDER BY r.nr`)
	if err != nil {
		return nil, fmt.Errorf("official: load: %w", err)
	}
	defer rows.Close()
	var out []source
	for rows.Next() {
		var src source
		var titles, geoms, modes []string
		if err := rows.Scan(&src.Nr, &src.Name, &src.Kind, &titles, &geoms, &modes); err != nil {
			return nil, err
		}
		lines := make([][]geo.Point, len(geoms))
		jumps := make([][]jump, len(geoms))
		for i, g := range geoms {
			pieces, err := parseLines(g)
			if err != nil {
				return nil, fmt.Errorf("official: route %s: %w", src.Nr, err)
			}
			lines[i], jumps[i] = join(pieces)
		}
		Orient(lines)
		for i, line := range lines {
			walks := [][]geo.Point{line}
			if modes[i] != "" {
				walks = split(line, jumps[i], 50, 100)
			}
			for k, w := range walks {
				p := part{Title: titles[i], Line: w}
				if len(walks) > 1 {
					p.Title = fmt.Sprintf("%s (%d/%d)", titles[i], k+1, len(walks))
				}
				if k > 0 {
					p.Transfer = modes[i]
				}
				src.Parts = append(src.Parts, p)
			}
		}
		out = append(out, src)
	}
	return out, rows.Err()
}

// parseLines reads a GeoJSON LineString or MultiLineString.
func parseLines(s string) ([][]geo.Point, error) {
	var g struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
	}
	if err := json.Unmarshal([]byte(s), &g); err != nil {
		return nil, err
	}
	var multi [][][2]float64
	switch g.Type {
	case "LineString":
		var line [][2]float64
		if err := json.Unmarshal(g.Coordinates, &line); err != nil {
			return nil, err
		}
		multi = [][][2]float64{line}
	case "MultiLineString":
		if err := json.Unmarshal(g.Coordinates, &multi); err != nil {
			return nil, err
		}
	default:
		return nil, fmt.Errorf("unexpected geometry %s", g.Type)
	}
	parts := make([][]geo.Point, len(multi))
	for i, l := range multi {
		for _, c := range l {
			parts[i] = append(parts[i], geo.Point{Lon: c[0], Lat: c[1]})
		}
	}
	return parts, nil
}

// hash identifies what a route is made of, to skip unchanged ones.
func (src source) hash() string {
	b, _ := json.Marshal(src)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// put creates or replaces the Alvyo item of src: a route for one stage, a
// journey for several. An item's id is kept where its kind stays the same,
// so likes, collections and hiked marks stay with it.
func (s *Syncer) put(ctx context.Context, owner uuid.UUID, src source, hash string, old item, exists bool) error {
	var contents []routes.Content
	for i, p := range src.Parts {
		c, err := s.Importer.Content(ctx, imports.Track{Name: p.Title, Points: p.Line})
		if err != nil {
			return fmt.Errorf("stage %d: %w", i+1, err)
		}
		contents = append(contents, c)
	}
	if len(contents) == 0 {
		return errors.New("no stages")
	}
	title := clip(src.Name)
	var routeID, journeyID *uuid.UUID
	switch {
	case len(contents) == 1 && exists && old.routeID != nil:
		r, err := s.Importer.Routes.Get(ctx, *old.routeID)
		if err != nil {
			return err
		}
		if _, err := s.Importer.Routes.Update(ctx, *old.routeID, r.Version,
			routes.Meta{Title: title, Description: r.Description, Visibility: "public", Tags: r.Tags}, &contents[0], owner); err != nil {
			return err
		}
		routeID = old.routeID
	case len(contents) == 1:
		r, err := s.Importer.Routes.Create(ctx, owner, routes.Meta{Title: title, Visibility: "public"}, contents[0])
		if err != nil {
			return err
		}
		id := uuid.MustParse(r.ID)
		routeID = &id
	case exists && old.journeyID != nil:
		if err := s.updateJourney(ctx, owner, *old.journeyID, title, src.Parts, contents); err != nil {
			return err
		}
		journeyID = old.journeyID
	default:
		stages := make([]journeys.PlannedStage, len(contents))
		for i, c := range contents {
			p := src.Parts[i]
			stages[i] = journeys.PlannedStage{Title: clip(p.Title), Content: c, TransferBefore: p.Transfer}
		}
		j, err := s.Importer.Journeys.CreatePlanned(ctx, owner, journeys.Meta{Title: title, Visibility: "public"}, stages)
		if err != nil {
			return err
		}
		id := uuid.MustParse(j.ID)
		journeyID = &id
	}
	if exists && (old.routeID != nil) != (routeID != nil) { // one stage became several, or back
		if err := s.remove(ctx, old); err != nil {
			return err
		}
	}
	_, err := s.DB.Exec(ctx, `
		INSERT INTO official (nr, kind, route_id, journey_id, hash) VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (nr) DO UPDATE SET kind = $2, route_id = $3, journey_id = $4, hash = $5`,
		src.Nr, src.Kind, routeID, journeyID, hash)
	return err
}

// updateJourney gives an official journey its new title and stages, keeping
// the stages that are there (their marks and notes) and their order.
func (s *Syncer) updateJourney(ctx context.Context, owner, id uuid.UUID, title string, parts []part, contents []routes.Content) error {
	js := s.Importer.Journeys
	j, err := js.Get(ctx, id)
	if err != nil {
		return err
	}
	if _, err := js.UpdateMeta(ctx, id, j.Version, journeys.Meta{Title: title, Description: j.Description,
		Visibility: "public", Tags: j.Tags}); err != nil {
		return err
	}
	for i, c := range contents {
		stageTitle, transfer := clip(parts[i].Title), parts[i].Transfer
		if i >= len(j.StageList) {
			stage, err := js.AddStageID(ctx, id, owner, journeys.NewStage{Title: stageTitle, TransferBefore: transfer})
			if err != nil {
				return err
			}
			if _, err := js.SetStageRoute(ctx, id, stage, owner, stageTitle, c); err != nil {
				return err
			}
			continue
		}
		st := j.StageList[i]
		stage := uuid.MustParse(st.ID)
		if err := js.UpdateStage(ctx, id, stage, st.Version, journeys.StagePatch{Title: &stageTitle, TransferBefore: &transfer}); err != nil {
			return err
		}
		if st.Route == nil {
			if _, err := js.SetStageRoute(ctx, id, stage, owner, stageTitle, c); err != nil {
				return err
			}
			continue
		}
		rid := uuid.MustParse(st.Route.ID)
		r, err := s.Importer.Routes.Get(ctx, rid)
		if err != nil {
			return err
		}
		if _, err := s.Importer.Routes.Update(ctx, rid, r.Version,
			routes.Meta{Title: stageTitle, Visibility: r.Visibility}, &c, owner); err != nil {
			return err
		}
	}
	for _, st := range j.StageList[min(len(contents), len(j.StageList)):] {
		if err := js.DeleteStage(ctx, id, uuid.MustParse(st.ID)); err != nil {
			return err
		}
	}
	return nil
}

// remove deletes the Alvyo item of a route Wanderland no longer has.
func (s *Syncer) remove(ctx context.Context, it item) error {
	if it.routeID != nil {
		if err := s.Importer.Routes.Delete(ctx, *it.routeID); err != nil && !errors.Is(err, routes.ErrNotFound) {
			return err
		}
	}
	if it.journeyID != nil {
		if err := s.Importer.Journeys.Delete(ctx, *it.journeyID); err != nil && !errors.Is(err, journeys.ErrNotFound) {
			return err
		}
	}
	return nil
}

// clip keeps a title within the 120 characters a route or journey allows.
func clip(s string) string {
	if utf8.RuneCountInString(s) <= 120 {
		return s
	}
	return string([]rune(s)[:119]) + "…"
}
