package httpapi

import (
	"context"
	"net/http"
	"os"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"
	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/packs"
	"github.com/tellbow/odysgeh/swiss/geo"
)

type packStatusOutput struct{ Body packs.Status }

type packFileInput struct {
	ID    string `path:"id" format:"uuid"`
	Layer string `path:"layer" enum:"landeskarte,wanderwege"`
	Token string `query:"t"`
}

// packItem finds what a pack of a route or journey covers.
type packItem struct {
	kind  string // "route" or "journey"
	path  string
	lines func(ctx context.Context, rawID, token string) (id uuid.UUID, lines [][]geo.Point, err error)
}

var errNoPacks = huma.Error503ServiceUnavailable("offline maps are not configured")

// packWriteTimeout is how long a pack download may take; the app resumes
// broken off downloads.
const packWriteTimeout = 30 * time.Minute

func registerPacks(api huma.API, d Deps) {
	items := []packItem{
		{kind: "route", path: "/routes", lines: func(ctx context.Context, rawID, token string) (uuid.UUID, [][]geo.Point, error) {
			r, _, err := loadRoute(ctx, d, rawID, token)
			if err != nil {
				return uuid.Nil, nil, err
			}
			var line []geo.Point
			for _, c := range r.Line() {
				line = append(line, geo.Point{Lon: c[0], Lat: c[1]})
			}
			return uuid.MustParse(r.ID), [][]geo.Point{line}, nil
		}},
		{kind: "journey", path: "/journeys", lines: func(ctx context.Context, rawID, token string) (uuid.UUID, [][]geo.Point, error) {
			j, _, err := loadJourney(ctx, d, rawID, token)
			if err != nil {
				return uuid.Nil, nil, err
			}
			id := uuid.MustParse(j.ID)
			lines, err := d.Journeys.StageLines(ctx, id)
			return id, lines, err
		}},
	}
	for _, it := range items {
		registerPackItem(api, d, it)
	}
}

func registerPackItem(api huma.API, d Deps, it packItem) {
	tags := []string{"offline"}
	key := func(id uuid.UUID, lines [][]geo.Point) (string, string) {
		return packs.Key(it.kind, id.String(), lines), it.kind + "-" + id.String() + "-"
	}

	huma.Register(api, huma.Operation{
		OperationID: "build-" + it.kind + "-pack", Method: http.MethodPost, Path: it.path + "/{id}/pack",
		Summary:     "Prepare the offline map of a " + it.kind,
		Description: "National map and hiking trails within 1 km, zoom 10–16, as PMTiles. Builds in the background; poll the status, then download each layer. 503 when not configured.",
		Tags:        tags,
	}, func(ctx context.Context, in *socialInput) (*packStatusOutput, error) {
		u, err := requireUser(ctx)
		if err != nil {
			return nil, err
		}
		if d.Packs == nil {
			return nil, errNoPacks
		}
		id, lines, err := it.lines(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		if len(lines) == 0 {
			return nil, huma.Error422UnprocessableEntity("no stage has a route yet")
		}
		k, prefix := key(id, lines)
		if st := d.Packs.Status(k); st.State == "ready" || st.State == "building" {
			return &packStatusOutput{Body: st}, nil
		}
		if !d.Limits.Pack.Allow(u.ID.String()) {
			return nil, errTooMany
		}
		tiles := packs.Corridor(lines, packs.BufferM)
		if len(tiles) > packs.MaxTiles {
			return nil, huma.Error422UnprocessableEntity("too long for one offline map; save the stages one by one")
		}
		st := d.Packs.Ensure(k, prefix, func(context.Context) ([]packs.Tile, error) { return tiles, nil })
		return &packStatusOutput{Body: st}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "get-" + it.kind + "-pack", Method: http.MethodGet, Path: it.path + "/{id}/pack",
		Summary: "Status of the offline map of a " + it.kind, Tags: tags,
	}, func(ctx context.Context, in *socialInput) (*packStatusOutput, error) {
		if d.Packs == nil {
			return nil, errNoPacks
		}
		id, lines, err := it.lines(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		k, _ := key(id, lines)
		return &packStatusOutput{Body: d.Packs.Status(k)}, nil
	})

	huma.Register(api, huma.Operation{
		OperationID: "download-" + it.kind + "-pack", Method: http.MethodGet, Path: it.path + "/{id}/pack/{layer}",
		Summary:     "Download one layer of the offline map (PMTiles)",
		Description: "Supports Range requests, so interrupted downloads can resume.",
		Tags:        tags,
	}, func(ctx context.Context, in *packFileInput) (*huma.StreamResponse, error) {
		if d.Packs == nil {
			return nil, errNoPacks
		}
		id, lines, err := it.lines(ctx, in.ID, in.Token)
		if err != nil {
			return nil, err
		}
		k, _ := key(id, lines)
		st := d.Packs.Status(k)
		var name string
		for _, f := range st.Files {
			if f.Layer == in.Layer {
				name = f.Name
			}
		}
		path, ok := d.Packs.Builder.Path(name)
		if !ok {
			return nil, huma.Error404NotFound("the offline map is not ready")
		}
		return &huma.StreamResponse{Body: func(hctx huma.Context) {
			r, w := humago.Unwrap(hctx)
			f, err := os.Open(path)
			if err != nil {
				http.Error(w, "the offline map is not ready", http.StatusNotFound)
				return
			}
			defer func() { _ = f.Close() }()
			d.Packs.Builder.Touch(k) // in use: keep it when pruning
			w.Header().Set("Content-Type", "application/vnd.pmtiles")
			w.Header().Set("Cache-Control", "private, max-age=86400")
			// Some hundred MB over a mountain hut's connection take longer
			// than the server's write timeout.
			_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(packWriteTimeout))
			http.ServeContent(w, r, name, time.Time{}, f)
		}}, nil
	})
}
