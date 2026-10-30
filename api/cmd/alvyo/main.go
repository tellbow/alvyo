// Command alvyo runs the alvyo API server and its maintenance subcommands.
//
//	alvyo serve                        run the HTTP API
//	alvyo migrate                      apply pending database migrations
//	alvyo openapi                      print the OpenAPI spec (for client code generation)
//	alvyo user ban|unban <username>    block or unblock an account
//	alvyo user role <username> <role>  set user, moderator or admin
//	alvyo route unpublish <id>         make a route private
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"golang.org/x/time/rate"

	"github.com/tellbow/alvyo/api/internal/admin"
	"github.com/tellbow/alvyo/api/internal/areas"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/bugs"
	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/config"
	"github.com/tellbow/alvyo/api/internal/db"
	"github.com/tellbow/alvyo/api/internal/discover"
	"github.com/tellbow/alvyo/api/internal/done"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/httpapi"
	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/live"
	"github.com/tellbow/alvyo/api/internal/mailer"
	"github.com/tellbow/alvyo/api/internal/official"
	"github.com/tellbow/alvyo/api/internal/og"
	"github.com/tellbow/alvyo/api/internal/packs"
	"github.com/tellbow/alvyo/api/internal/peaks"
	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/places"
	"github.com/tellbow/alvyo/api/internal/precip"
	"github.com/tellbow/alvyo/api/internal/reminders"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/snow"
	"github.com/tellbow/alvyo/api/internal/steep"
	"github.com/tellbow/alvyo/api/internal/telemetry"
	"github.com/tellbow/alvyo/api/internal/travel"
	"github.com/tellbow/alvyo/api/internal/weather"
	"github.com/tellbow/alvyo/swiss/elevation"
	"github.com/tellbow/alvyo/swiss/ojp"
)

// version is set at build time: -ldflags "-X main.version=<sha>".
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: alvyo serve|migrate|openapi|user|route")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2:]); err != nil {
		slog.Error("alvyo failed", "err", err)
		os.Exit(1)
	}
}

func run(cmd string, args []string) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	switch cmd {
	case "serve":
		return serve(ctx)
	case "migrate":
		return migrate(ctx)
	case "openapi":
		return printOpenAPI()
	case "user", "route":
		return adminCommand(ctx, cmd, args)
	default:
		return fmt.Errorf("unknown command %q", cmd)
	}
}

func serve(ctx context.Context) error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	slog.SetDefault(slog.New(telemetry.WithTraceIDs(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))))
	var metrics *http.Server
	if telemetry.Tracing() || cfg.MetricsListen != "" {
		tel, err := telemetry.Start(ctx, "alvyo-api", version, telemetry.Tracing())
		if err != nil {
			return fmt.Errorf("telemetry: %w", err)
		}
		if cfg.MetricsListen != "" {
			mux := http.NewServeMux()
			mux.Handle("GET /metrics", tel.Metrics)
			metrics = &http.Server{Addr: cfg.MetricsListen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
		}
		defer func() {
			// What is still buffered, after the server has stopped.
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := tel.Shutdown(ctx); err != nil {
				slog.Warn("telemetry shutdown", "err", err)
			}
		}()
	}

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	sender, err := mailer.NewSMTP(cfg.SMTP)
	if err != nil {
		return err
	}
	routeStore := &routes.Store{DB: pool}
	journeyStore := &journeys.Store{DB: pool, Routes: routeStore}
	var heights elevation.Sampler = &elevation.GeoAdmin{
		BaseURL:   cfg.ElevationURL,
		UserAgent: "alvyo/" + version + " (+https://github.com/tellbow/alvyo)",
	}
	snowStore := &snow.Store{DB: pool}
	var terrain steep.Terrain
	if cfg.SwissALTI3DDir != "" {
		alti := &elevation.SwissALTI3D{Dir: cfg.SwissALTI3DDir}
		heights = elevation.Fallback{First: alti, Second: heights}
		snowStore.Terrain = alti // the slope under snow along routes
		terrain = alti
	}
	router := &routing.Router{
		GraphHopper: &routing.GraphHopper{URL: cfg.GraphHopper},
		Elevation:   heights,
		Trails:      &routing.TrailMatcher{DB: pool},
		Outlines:    &routing.Outliner{DB: pool},
	}
	packService := &packs.Service{
		Builder: &packs.Builder{
			TilesURL: cfg.TilesURL, Dir: filepath.Join(cfg.CacheDir, "packs"),
			Rate: rate.NewLimiter(40, 40), // the tile cache allows 60 requests/s per address
		},
		// Packs are rebuilt on demand. The cache volume (1 GiB in the cluster)
		// also holds the OpenGraph images.
		MaxAge: 7 * 24 * time.Hour, MaxBytes: 512 << 20,
	}
	go packService.PruneEvery(ctx, time.Hour)
	peakService := &peaks.Service{DB: pool, TilesURL: cfg.TilesURL, Dir: filepath.Join(cfg.CacheDir, "peaks")}
	_, _, _ = peakService.File() // built in the background unless there
	photoStore := &photos.Store{DB: pool, Files: &photos.Files{Dir: cfg.PhotosDir}}
	go photoStore.SweepEvery(ctx, time.Minute) // files of deleted photos
	liveStore := &live.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL}
	go liveStore.CheckEvery(ctx, time.Minute) // overdue hikes, old positions
	reminderStore := &reminders.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL}
	go reminderStore.CheckEvery(ctx, 15*time.Minute) // before journeys start
	areaFinder := &areas.Finder{DB: pool, URL: cfg.AreasURL, UserAgent: "alvyo/" + version + " (+https://github.com/tellbow/alvyo)"}
	go areaFinder.PruneEvery(ctx, 24*time.Hour) // old answers from geo.admin
	forecast := &weather.Forecast{UserAgent: "alvyo/" + version + " (+https://github.com/tellbow/alvyo)"}
	go forecast.Keep(ctx, time.Hour) // MeteoSwiss updates hourly
	importer := &imports.Importer{Router: router, Routes: routeStore, Journeys: journeyStore}
	// The official routes after each wanderland-import (a few a year).
	go (&official.Syncer{DB: pool, Importer: importer}).SyncEvery(ctx, 6*time.Hour)
	var planner httpapi.Planner
	if cfg.OJPToken != "" {
		planner = &ojp.Client{URL: cfg.OJPURL, Token: cfg.OJPToken, RequestorRef: "alvyo/" + version}
	}
	var limits httpapi.Limits // zero value: defaults
	bugStore := &bugs.Store{DB: pool}
	if cfg.GitHubToken != "" {
		bugStore.GitHub = &bugs.GitHub{Repo: cfg.GitHubRepo, Token: cfg.GitHubToken}
	}
	if cfg.RelaxedLimits {
		slog.Warn("relaxed rate limits (ALVYO_RELAXED_LIMITS): for tests only")
		limits = httpapi.RelaxedLimits()
	}
	oidc := oidcProviders(cfg)
	deps := httpapi.Deps{
		DB:          pool,
		Auth:        &auth.Service{DB: pool, Mail: sender, PublicURL: cfg.PublicURL, Revoke: oidc.Revoke},
		Router:      router,
		Routes:      routeStore,
		Journeys:    journeyStore,
		Importer:    importer,
		Places:      &places.Store{DB: pool, Names: &places.GeoAdmin{}},
		Live:        liveStore,
		Travel:      &travel.Store{DB: pool},
		Areas:       areaFinder,
		Weather:     forecast,
		Grants:      &grants.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL},
		Collections: &collections.Store{DB: pool},
		Precip:      &precip.Store{DB: pool},
		Snow:        snowStore,
		Terrain:     terrain,
		Peaks:       peakService,
		Discover:    &discover.Store{DB: pool},
		Community:   &community.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL},
		Done:        &done.Store{DB: pool},
		Photos:      photoStore,
		OIDC:        oidc,
		Packs:       packService,
		Planner:     planner,
		Images:      &og.Renderer{TilesURL: cfg.TilesURL, CacheDir: cfg.CacheDir},
		Bugs:        bugStore,
		Admin: &admin.Store{DB: pool, GraphHopper: cfg.GraphHopper, AltiDir: cfg.SwissALTI3DDir, Probes: []admin.Probe{
			{Name: "GraphHopper", URL: cfg.GraphHopper + "/health"},
			{Name: "Kachel-Cache", URL: cfg.TilesURL + "/healthz"},
			{Name: "geo.admin", URL: "https://api3.geo.admin.ch/rest/services/height?easting=2600000&northing=1200000"},
			{Name: "MeteoSwiss (data.geo.admin.ch)", URL: "https://data.geo.admin.ch/api/stac/v1/collections/ch.meteoschweiz.ogd-local-forecasting"},
			{Name: "OJP (Verbindungen)", URL: cfg.OJPURL},
			{Name: "Mailserver", URL: "tcp://" + net.JoinHostPort(cfg.SMTP.Host, strconv.Itoa(cfg.SMTP.Port))},
		}},
		Reminders:  reminderStore,
		Version:    version,
		PublicURL:  cfg.PublicURL,
		TrustProxy: cfg.TrustProxy,
		Limits:     limits,
	}
	handler, _ := httpapi.New(deps)
	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           telemetry.Handler(handler),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       2 * time.Minute, // uploads (photos, track files) of 20 MB from phones
		// From the end of the headers, so it includes reading the upload;
		// offline map downloads extend it (packWriteTimeout).
		WriteTimeout: 3 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}

	// The admin portal's API, for the internal admin host only.
	adminDeps := deps
	adminDeps.PublicURL = cfg.AdminURL
	adminHandler, _ := httpapi.NewAdmin(adminDeps)
	admin := &http.Server{Addr: cfg.AdminListen, Handler: telemetry.Handler(adminHandler), ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout: time.Minute, WriteTimeout: time.Minute, IdleTimeout: 120 * time.Second}
	defer func() { _ = admin.Close() }()

	errc := make(chan error, 3)
	go func() {
		slog.Info("listening", "addr", cfg.Listen, "version", version)
		errc <- srv.ListenAndServe()
	}()
	go func() {
		slog.Info("admin", "addr", cfg.AdminListen)
		errc <- admin.ListenAndServe()
	}()
	if metrics != nil {
		go func() {
			slog.Info("metrics", "addr", metrics.Addr)
			errc <- metrics.ListenAndServe()
		}()
		defer func() { _ = metrics.Close() }()
	}
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func migrate(ctx context.Context) error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	n, err := db.Migrate(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	slog.Info("migrations applied", "count", n)
	return nil
}

func adminCommand(ctx context.Context, cmd string, args []string) error {
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	usage := errors.New("usage: alvyo user ban|unban <username> | user role <username> <role> | route unpublish <id> | route retrail")
	switch {
	case cmd == "user" && len(args) == 2 && args[0] == "ban":
		err = admin.Ban(ctx, pool, args[1])
	case cmd == "user" && len(args) == 2 && args[0] == "unban":
		err = admin.Unban(ctx, pool, args[1])
	case cmd == "user" && len(args) == 3 && args[0] == "role":
		err = admin.SetRole(ctx, pool, args[1], args[2])
	case cmd == "route" && len(args) == 2 && args[0] == "unpublish":
		err = admin.Unpublish(ctx, pool, args[1])
	case cmd == "route" && len(args) == 1 && args[0] == "retrail":
		// After loading the official trail network (tlm-import): routes
		// planned without it.
		var n int
		n, err = (&routes.Store{DB: pool}).Retrail(ctx, &routing.TrailMatcher{DB: pool})
		slog.Info("routes retrailed", "changed", n)
	default:
		return usage
	}
	if err != nil {
		return err
	}
	slog.Info("done", "command", cmd, "args", args)
	return nil
}

func printOpenAPI() error {
	// The admin API's: the public operations and the admin portal's.
	_, api := httpapi.NewAdmin(httpapi.Deps{Version: version})
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(api.OpenAPI())
}

// oidcProviders sets up sign-in through the configured providers.
func oidcProviders(cfg config.Config) *auth.OIDC {
	o := &auth.OIDC{CallbackURL: func(id string) string {
		return cfg.PublicURL + "/api/v1/auth/oidc/" + id + "/callback"
	}}
	for _, p := range cfg.OIDC {
		o.Providers = append(o.Providers, auth.OIDCProvider(p))
	}
	return o
}
