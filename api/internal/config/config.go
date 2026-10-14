// Package config reads the API configuration from environment variables.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/tellbow/alvyo/api/internal/mailer"
)

// Config is the runtime configuration of the Alvyo API.
type Config struct {
	Listen string // ALVYO_LISTEN, default ":8080"
	// MetricsListen serves /metrics for Prometheus apart from the API
	// (not behind the ingress): ALVYO_METRICS_LISTEN, e.g. ":9464"; off if
	// empty.
	MetricsListen string
	DatabaseURL   string     // ALVYO_DATABASE_URL (required)
	LogLevel      slog.Level // ALVYO_LOG_LEVEL: debug, info, warn, error
	PublicURL     string     // ALVYO_PUBLIC_URL: origin of the web app, default http://localhost:5173
	TrustProxy    bool       // ALVYO_TRUST_PROXY: behind our reverse proxy
	GraphHopper   string     // ALVYO_GRAPHHOPPER_URL, default http://localhost:8989
	TilesURL      string     // ALVYO_TILES_URL: our tile cache, default http://localhost:8081
	CacheDir      string     // ALVYO_CACHE_DIR: rendered images etc., default <tmp>/alvyo
	PhotosDir     string     // ALVYO_PHOTOS_DIR: uploaded photos (keep and back up), default data/photos
	// OJP (public transport connections): ALVYO_OJP_TOKEN is the
	// opentransportdata.swiss API key; without it the feature is off.
	OJPURL   string // ALVYO_OJP_URL, default the OJP 2.0 production endpoint
	OJPToken string
	// RelaxedLimits (ALVYO_RELAXED_LIMITS=true) lifts the per-IP signup
	// limit for end-to-end tests. Never set it in production.
	RelaxedLimits bool
	// Bug reports open issues in ALVYO_GITHUB_REPO (default tellbow/alvyo-feedback, private)
	// with ALVYO_GITHUB_TOKEN (issues: write); without it they are only kept.
	GitHubRepo  string
	GitHubToken string
	SMTP        mailer.SMTPConfig
	// OIDC sign-in providers: ALVYO_OIDC_PROVIDERS lists ids (a-z, 0-9),
	// each with ALVYO_OIDC_<ID>_ISSUER, _CLIENT_ID, _CLIENT_SECRET and
	// optionally _NAME (the button label).
	OIDC []OIDCProvider
}

// OIDCProvider is one configured OpenID Connect provider.
type OIDCProvider struct {
	ID, Name, Issuer, ClientID, ClientSecret string
}

var providerID = regexp.MustCompile(`^[a-z0-9]{1,20}$`)

func oidcProviders() ([]OIDCProvider, error) {
	var out []OIDCProvider
	for id := range strings.SplitSeq(os.Getenv("ALVYO_OIDC_PROVIDERS"), ",") {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if !providerID.MatchString(id) {
			return nil, fmt.Errorf("ALVYO_OIDC_PROVIDERS: %q: use a-z and 0-9", id)
		}
		env := "ALVYO_OIDC_" + strings.ToUpper(id) + "_"
		p := OIDCProvider{ID: id, Name: getenv(env+"NAME", id), Issuer: os.Getenv(env + "ISSUER"),
			ClientID: os.Getenv(env + "CLIENT_ID"), ClientSecret: os.Getenv(env + "CLIENT_SECRET")}
		if p.Issuer == "" || p.ClientID == "" || p.ClientSecret == "" {
			return nil, fmt.Errorf("OIDC provider %s: %sISSUER, %sCLIENT_ID and %sCLIENT_SECRET are required", id, env, env, env)
		}
		out = append(out, p)
	}
	return out, nil
}

// FromEnv loads the configuration from the environment.
//
// SMTP: ALVYO_SMTP_HOST (localhost), ALVYO_SMTP_PORT (1025),
// ALVYO_SMTP_USER, ALVYO_SMTP_PASSWORD, ALVYO_SMTP_TLS (none|starttls|tls),
// ALVYO_MAIL_FROM. The defaults match Mailpit from infra/compose.yaml.
func FromEnv() (Config, error) {
	c := Config{
		Listen:        getenv("ALVYO_LISTEN", ":8080"),
		MetricsListen: os.Getenv("ALVYO_METRICS_LISTEN"),
		DatabaseURL:   os.Getenv("ALVYO_DATABASE_URL"),
		PublicURL:     strings.TrimSuffix(getenv("ALVYO_PUBLIC_URL", "http://localhost:5173"), "/"),
		TrustProxy:    os.Getenv("ALVYO_TRUST_PROXY") == "true",
		GraphHopper:   getenv("ALVYO_GRAPHHOPPER_URL", "http://localhost:8989"),
		TilesURL:      getenv("ALVYO_TILES_URL", "http://localhost:8081"),
		CacheDir:      getenv("ALVYO_CACHE_DIR", filepath.Join(os.TempDir(), "alvyo")),
		PhotosDir:     getenv("ALVYO_PHOTOS_DIR", filepath.Join("data", "photos")),
		RelaxedLimits: os.Getenv("ALVYO_RELAXED_LIMITS") == "true",
		OJPURL:        getenv("ALVYO_OJP_URL", "https://api.opentransportdata.swiss/ojp20"),
		OJPToken:      os.Getenv("ALVYO_OJP_TOKEN"),
		GitHubRepo:    getenv("ALVYO_GITHUB_REPO", "tellbow/alvyo-feedback"),
		GitHubToken:   os.Getenv("ALVYO_GITHUB_TOKEN"),
		SMTP: mailer.SMTPConfig{
			Host:     getenv("ALVYO_SMTP_HOST", "localhost"),
			Username: os.Getenv("ALVYO_SMTP_USER"),
			Password: os.Getenv("ALVYO_SMTP_PASSWORD"),
			TLS:      getenv("ALVYO_SMTP_TLS", "none"),
			From:     getenv("ALVYO_MAIL_FROM", "Alvyo <noreply@localhost>"),
		},
	}
	if c.DatabaseURL == "" {
		return c, errors.New("ALVYO_DATABASE_URL is required")
	}
	if err := c.LogLevel.UnmarshalText([]byte(getenv("ALVYO_LOG_LEVEL", "info"))); err != nil {
		return c, err
	}
	port, err := strconv.Atoi(getenv("ALVYO_SMTP_PORT", "1025"))
	if err != nil {
		return c, fmt.Errorf("ALVYO_SMTP_PORT: %w", err)
	}
	c.SMTP.Port = port
	if c.OIDC, err = oidcProviders(); err != nil {
		return c, err
	}
	return c, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
