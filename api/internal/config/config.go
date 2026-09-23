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

	"github.com/tellbow/odysgeh/api/internal/mailer"
)

// Config is the runtime configuration of the odysgeh API.
type Config struct {
	Listen      string     // ODYSGEH_LISTEN, default ":8080"
	DatabaseURL string     // ODYSGEH_DATABASE_URL (required)
	LogLevel    slog.Level // ODYSGEH_LOG_LEVEL: debug, info, warn, error
	PublicURL   string     // ODYSGEH_PUBLIC_URL: origin of the web app, default http://localhost:5173
	TrustProxy  bool       // ODYSGEH_TRUST_PROXY: behind our reverse proxy
	GraphHopper string     // ODYSGEH_GRAPHHOPPER_URL, default http://localhost:8989
	TilesURL    string     // ODYSGEH_TILES_URL: our tile cache, default http://localhost:8081
	CacheDir    string     // ODYSGEH_CACHE_DIR: rendered images etc., default <tmp>/odysgeh
	PhotosDir   string     // ODYSGEH_PHOTOS_DIR: uploaded photos (keep and back up), default data/photos
	// OJP (public transport connections): ODYSGEH_OJP_TOKEN is the
	// opentransportdata.swiss API key; without it the feature is off.
	OJPURL   string // ODYSGEH_OJP_URL, default the OJP 2.0 production endpoint
	OJPToken string
	// RelaxedLimits (ODYSGEH_RELAXED_LIMITS=true) lifts the per-IP signup
	// limit for end-to-end tests. Never set it in production.
	RelaxedLimits bool
	SMTP          mailer.SMTPConfig
	// OIDC sign-in providers: ODYSGEH_OIDC_PROVIDERS lists ids (a-z, 0-9),
	// each with ODYSGEH_OIDC_<ID>_ISSUER, _CLIENT_ID, _CLIENT_SECRET and
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
	for id := range strings.SplitSeq(os.Getenv("ODYSGEH_OIDC_PROVIDERS"), ",") {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if !providerID.MatchString(id) {
			return nil, fmt.Errorf("ODYSGEH_OIDC_PROVIDERS: %q: use a-z and 0-9", id)
		}
		env := "ODYSGEH_OIDC_" + strings.ToUpper(id) + "_"
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
// SMTP: ODYSGEH_SMTP_HOST (localhost), ODYSGEH_SMTP_PORT (1025),
// ODYSGEH_SMTP_USER, ODYSGEH_SMTP_PASSWORD, ODYSGEH_SMTP_TLS (none|starttls|tls),
// ODYSGEH_MAIL_FROM. The defaults match Mailpit from infra/compose.yaml.
func FromEnv() (Config, error) {
	c := Config{
		Listen:        getenv("ODYSGEH_LISTEN", ":8080"),
		DatabaseURL:   os.Getenv("ODYSGEH_DATABASE_URL"),
		PublicURL:     strings.TrimSuffix(getenv("ODYSGEH_PUBLIC_URL", "http://localhost:5173"), "/"),
		TrustProxy:    os.Getenv("ODYSGEH_TRUST_PROXY") == "true",
		GraphHopper:   getenv("ODYSGEH_GRAPHHOPPER_URL", "http://localhost:8989"),
		TilesURL:      getenv("ODYSGEH_TILES_URL", "http://localhost:8081"),
		CacheDir:      getenv("ODYSGEH_CACHE_DIR", filepath.Join(os.TempDir(), "odysgeh")),
		PhotosDir:     getenv("ODYSGEH_PHOTOS_DIR", filepath.Join("data", "photos")),
		RelaxedLimits: os.Getenv("ODYSGEH_RELAXED_LIMITS") == "true",
		OJPURL:        getenv("ODYSGEH_OJP_URL", "https://api.opentransportdata.swiss/ojp20"),
		OJPToken:      os.Getenv("ODYSGEH_OJP_TOKEN"),
		SMTP: mailer.SMTPConfig{
			Host:     getenv("ODYSGEH_SMTP_HOST", "localhost"),
			Username: os.Getenv("ODYSGEH_SMTP_USER"),
			Password: os.Getenv("ODYSGEH_SMTP_PASSWORD"),
			TLS:      getenv("ODYSGEH_SMTP_TLS", "none"),
			From:     getenv("ODYSGEH_MAIL_FROM", "odysgeh <noreply@localhost>"),
		},
	}
	if c.DatabaseURL == "" {
		return c, errors.New("ODYSGEH_DATABASE_URL is required")
	}
	if err := c.LogLevel.UnmarshalText([]byte(getenv("ODYSGEH_LOG_LEVEL", "info"))); err != nil {
		return c, err
	}
	port, err := strconv.Atoi(getenv("ODYSGEH_SMTP_PORT", "1025"))
	if err != nil {
		return c, fmt.Errorf("ODYSGEH_SMTP_PORT: %w", err)
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
