// Package httpapi wires the HTTP routes of the Alvyo API.
package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"path"
	"reflect"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tellbow/alvyo/api/internal/areas"
	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/collections"
	"github.com/tellbow/alvyo/api/internal/community"
	"github.com/tellbow/alvyo/api/internal/discover"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/imports"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/live"
	"github.com/tellbow/alvyo/api/internal/og"
	"github.com/tellbow/alvyo/api/internal/packs"
	"github.com/tellbow/alvyo/api/internal/photos"
	"github.com/tellbow/alvyo/api/internal/places"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/travel"
	"github.com/tellbow/alvyo/api/internal/weather"
)

// Prefix is the path under which the versioned API is served.
const Prefix = "/api/v1"

func init() {
	// Responses never contain null arrays (handlers return empty slices), so
	// the schema — and the generated TypeScript types — should not allow it.
	huma.DefaultArrayNullable = false
}

// Deps are the dependencies of the HTTP handlers.
type Deps struct {
	DB          *pgxpool.Pool
	Auth        *auth.Service
	Router      *routing.Router
	Routes      *routes.Store
	Journeys    *journeys.Store
	Places      *places.Store
	Areas       *areas.Finder // protected areas along routes
	Weather     *weather.Forecast
	Live        *live.Store   // hikes shared with contacts
	Travel      *travel.Store // homes and the way to and from journeys
	Grants      *grants.Store
	Collections *collections.Store
	Discover    *discover.Store
	Community   *community.Store
	Photos      *photos.Store
	OIDC        *auth.OIDC // sign-in providers; nil for none
	Packs       *packs.Service
	Planner     Planner // public transport connections; nil when not configured
	Importer    *imports.Importer
	Komoot      *imports.Komoot
	Images      *og.Renderer
	Version     string // git SHA or release tag, shown for the AGPL source link
	PublicURL   string // origin of the web app: CSRF check and cookie Secure flag
	TrustProxy  bool   // take the client IP from X-Forwarded-For
	Limits      Limits // zero value: DefaultLimits
}

// Internal errors are logged, not shown: their messages can hold SQL, file
// paths or the answers of other services.
func init() {
	newError := huma.NewError
	huma.NewError = func(status int, msg string, errs ...error) huma.StatusError {
		if status >= 500 {
			if err := errors.Join(errs...); err != nil {
				slog.Error("internal error", "status", status, "msg", msg, "err", err)
			}
			errs = nil
		}
		return newError(status, msg, errs...)
	}
}

// New returns the root HTTP handler and the huma API (for OpenAPI export).
func New(d Deps) (http.Handler, huma.API) {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := d.DB.Ping(ctx); err != nil {
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		_, _ = w.Write([]byte("ok\n"))
	})

	cfg := huma.DefaultConfig("Alvyo API", d.Version)
	cfg.CreateHooks = nil // no $schema links in response bodies
	cfg.Components.Schemas = huma.NewMapRegistry("#/components/schemas/", schemaNamer)
	cfg.Servers = []*huma.Server{{URL: Prefix}}
	api := humago.NewWithPrefix(mux, Prefix, cfg)

	if d.Limits == (Limits{}) {
		d.Limits = DefaultLimits()
	}
	registerMeta(api, d)
	registerAuth(api, d)
	registerAccount(api, d)
	registerRouting(api, d)
	registerAreas(api, d)
	registerWeather(api, d)
	registerLive(api, d)
	registerRoutes(api, d)
	registerRevisions(api, d)
	registerJourneys(api, d)
	registerJourneyPlan(api, d)
	registerPlaces(api, d)
	registerGrants(api, d)
	registerCollections(api, d)
	registerTags(api, d)
	registerConnections(api, d)
	registerTravel(api, d)
	registerImports(api, d)
	registerHikes(api, d)
	registerDiscover(api, d)
	registerCommunity(api, d)
	registerPhotos(api, d)
	registerPasskeys(api, d)
	registerOIDC(api, d)
	registerPacks(api, d)

	h := withCompression(mux)
	if d.Auth != nil {
		h = withSession(h, d.Auth, d.secureCookies())
	}
	h = withOriginCheck(h, d.PublicURL)
	h = withSecurityHeaders(h)
	h = withAccessLog(h)
	h = withClientIP(h, d.TrustProxy)
	return h, api
}

// schemaPrefixes keep schema names unique across packages that use the same
// type names (routes.Summary vs journeys.Summary …).
var schemaPrefixes = map[string]string{"routes": "Route", "journeys": "Journey", "collections": "Collection", "ojp": "Transit", "discover": "Discover"}

func schemaNamer(t reflect.Type, hint string) string {
	name := huma.DefaultSchemaNamer(t, hint)
	for t.Kind() == reflect.Pointer || t.Kind() == reflect.Slice || t.Kind() == reflect.Array {
		t = t.Elem()
	}
	if p := schemaPrefixes[path.Base(t.PkgPath())]; p != "" && !strings.HasPrefix(name, p) {
		return p + name
	}
	return name
}

type versionOutput struct {
	Body struct {
		Version string `json:"version" doc:"Deployed version (git SHA or tag)"`
		Source  string `json:"source" doc:"Source code of this deployment (AGPL-3.0)"`
	}
}

func registerMeta(api huma.API, d Deps) {
	huma.Register(api, huma.Operation{
		OperationID: "get-version",
		Method:      http.MethodGet,
		Path:        "/version",
		Summary:     "Deployed version and source code location",
		Tags:        []string{"meta"},
	}, func(context.Context, *struct{}) (*versionOutput, error) {
		out := &versionOutput{}
		out.Body.Version = d.Version
		out.Body.Source = "https://github.com/tellbow/alvyo"
		return out, nil
	})
}
