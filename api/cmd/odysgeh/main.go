// Command odysgeh runs the odysgeh API server and its maintenance subcommands.
//
//	odysgeh serve                        run the HTTP API
//	odysgeh migrate                      apply pending database migrations
//	odysgeh openapi                      print the OpenAPI spec (for client code generation)
//	odysgeh user ban|unban <username>    block or unblock an account
//	odysgeh user role <username> <role>  set user, moderator or admin
//	odysgeh route unpublish <id>         make a route private
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/time/rate"

	"github.com/tellbow/odysgeh/api/internal/admin"
	"github.com/tellbow/odysgeh/api/internal/areas"
	"github.com/tellbow/odysgeh/api/internal/auth"
	"github.com/tellbow/odysgeh/api/internal/collections"
	"github.com/tellbow/odysgeh/api/internal/community"
	"github.com/tellbow/odysgeh/api/internal/config"
	"github.com/tellbow/odysgeh/api/internal/db"
	"github.com/tellbow/odysgeh/api/internal/discover"
	"github.com/tellbow/odysgeh/api/internal/grants"
	"github.com/tellbow/odysgeh/api/internal/httpapi"
	"github.com/tellbow/odysgeh/api/internal/imports"
	"github.com/tellbow/odysgeh/api/internal/journeys"
	"github.com/tellbow/odysgeh/api/internal/live"
	"github.com/tellbow/odysgeh/api/internal/mailer"
	"github.com/tellbow/odysgeh/api/internal/og"
	"github.com/tellbow/odysgeh/api/internal/packs"
	"github.com/tellbow/odysgeh/api/internal/photos"
	"github.com/tellbow/odysgeh/api/internal/places"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/swiss/elevation"
	"github.com/tellbow/odysgeh/swiss/ojp"
)

// version is set at build time: -ldflags "-X main.version=<sha>".
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: odysgeh serve|migrate|openapi|user|route")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2:]); err != nil {
		slog.Error("odysgeh failed", "err", err)
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
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel})))

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
	router := &routing.Router{
		GraphHopper: &routing.GraphHopper{URL: cfg.GraphHopper},
		Elevation:   &elevation.GeoAdmin{UserAgent: "odysgeh/" + version + " (+https://github.com/tellbow/odysgeh)"},
		Trails:      &routing.TrailMatcher{DB: pool},
	}
	webAuthn, err := auth.NewWebAuthn(cfg.PublicURL)
	if err != nil {
		return fmt.Errorf("passkeys: %w", err)
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
	photoStore := &photos.Store{DB: pool, Files: &photos.Files{Dir: cfg.PhotosDir}}
	go photoStore.SweepEvery(ctx, time.Minute) // files of deleted photos
	liveStore := &live.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL}
	go liveStore.CheckEvery(ctx, time.Minute) // overdue hikes, old positions
	var planner httpapi.Planner
	if cfg.OJPToken != "" {
		planner = &ojp.Client{URL: cfg.OJPURL, Token: cfg.OJPToken, RequestorRef: "odysgeh/" + version}
	}
	var limits httpapi.Limits // zero value: defaults
	if cfg.RelaxedLimits {
		slog.Warn("relaxed rate limits (ODYSGEH_RELAXED_LIMITS): for tests only")
		limits = httpapi.RelaxedLimits()
	}
	handler, _ := httpapi.New(httpapi.Deps{
		DB:          pool,
		Auth:        &auth.Service{DB: pool, Mail: sender, PublicURL: cfg.PublicURL, WebAuthn: webAuthn},
		Router:      router,
		Routes:      routeStore,
		Journeys:    journeyStore,
		Importer:    &imports.Importer{Router: router, Routes: routeStore, Journeys: journeyStore},
		Komoot:      &imports.Komoot{API: imports.KomootAPI},
		Places:      &places.Store{DB: pool, Names: &places.GeoAdmin{}},
		Live:        liveStore,
		Areas:       &areas.Finder{DB: pool, UserAgent: "odysgeh/" + version + " (+https://github.com/tellbow/odysgeh)"},
		Grants:      &grants.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL},
		Collections: &collections.Store{DB: pool},
		Discover:    &discover.Store{DB: pool},
		Community:   &community.Store{DB: pool, Mail: sender, PublicURL: cfg.PublicURL},
		Photos:      photoStore,
		OIDC:        oidcProviders(cfg),
		Packs:       packService,
		Planner:     planner,
		Images:      &og.Renderer{TilesURL: cfg.TilesURL, CacheDir: cfg.CacheDir},
		Version:     version,
		PublicURL:   cfg.PublicURL,
		TrustProxy:  cfg.TrustProxy,
		Limits:      limits,
	})
	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       2 * time.Minute, // uploads (photos, track files) of 20 MB from phones
		// From the end of the headers, so it includes reading the upload;
		// offline map downloads extend it (packWriteTimeout).
		WriteTimeout: 3 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", cfg.Listen, "version", version)
		errc <- srv.ListenAndServe()
	}()
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

	usage := errors.New("usage: odysgeh user ban|unban <username> | user role <username> <role> | route unpublish <id>")
	switch {
	case cmd == "user" && len(args) == 2 && args[0] == "ban":
		err = admin.Ban(ctx, pool, args[1])
	case cmd == "user" && len(args) == 2 && args[0] == "unban":
		err = admin.Unban(ctx, pool, args[1])
	case cmd == "user" && len(args) == 3 && args[0] == "role":
		err = admin.SetRole(ctx, pool, args[1], args[2])
	case cmd == "route" && len(args) == 2 && args[0] == "unpublish":
		err = admin.Unpublish(ctx, pool, args[1])
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
	_, api := httpapi.New(httpapi.Deps{Version: version})
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
