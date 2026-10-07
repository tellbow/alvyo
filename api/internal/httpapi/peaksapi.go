package httpapi

import (
	"context"
	"errors"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"

	"github.com/tellbow/alvyo/api/internal/peaks"
)

func registerPeaks(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "download-peaks-pack",
		Method:      http.MethodGet,
		Path:        "/peaks/pack",
		Summary:     "The pack for recognising mountains in the camera view",
		Description: "A height grid of Switzerland and about 50 km around it and the named summits, gzipped " +
			"(format: api/internal/peaks). 503 with Retry-After while it is being built. Supports Range requests.",
		Tags: []string{"peaks"},
	}, func(ctx context.Context, _ *struct{}) (*huma.StreamResponse, error) {
		if _, err := requireUser(ctx); err != nil {
			return nil, err
		}
		path, built, err := d.Peaks.File()
		if errors.Is(err, peaks.ErrBuilding) {
			return nil, huma.ErrorWithHeaders(huma.Error503ServiceUnavailable("the pack is being built, retry soon"),
				http.Header{"Retry-After": {"30"}})
		}
		if err != nil {
			return nil, err
		}
		return &huma.StreamResponse{Body: func(hctx huma.Context) {
			r, w := humago.Unwrap(hctx)
			f, err := os.Open(path)
			if err != nil {
				http.Error(w, "the pack is being built, retry soon", http.StatusServiceUnavailable)
				return
			}
			defer func() { _ = f.Close() }()
			w.Header().Set("Content-Type", "application/octet-stream")
			w.Header().Set("Cache-Control", "private, max-age=86400")
			// The app keeps it and asks again with If-None-Match.
			w.Header().Set("ETag", strconv.Quote(strconv.Itoa(peaks.Version)+"-"+strconv.FormatInt(built.Unix(), 10)))
			_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(packWriteTimeout))
			http.ServeContent(w, r, "peaks.bin.gz", built, f)
		}}, nil
	})
}
