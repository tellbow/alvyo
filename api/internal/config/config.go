// Package config reads the API configuration from environment variables.
package config

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
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
	// AdminListen serves the API with the admin portal's endpoints under
	// AdminPrefix, for the internal admin host only (never behind the public
	// ingress): ALVYO_ADMIN_LISTEN, default ":8082".
	AdminListen string
	AdminURL    string // ALVYO_ADMIN_URL: origin of the admin portal, default PublicURL
	// AdminJobs are the cron jobs the admin portal shows and starts by hand
	// (ALVYO_ADMIN_JOBS, comma-separated); in the cluster only.
	AdminJobs   []string
	DatabaseURL string     // ALVYO_DATABASE_URL (required)
	LogLevel    slog.Level // ALVYO_LOG_LEVEL: debug, info, warn, error
	PublicURL   string     // ALVYO_PUBLIC_URL: origin of the web app, default http://localhost:5173
	TrustProxy  bool       // ALVYO_TRUST_PROXY: behind our reverse proxy
	GraphHopper string     // ALVYO_GRAPHHOPPER_URL, default http://localhost:8989
	TilesURL    string     // ALVYO_TILES_URL: our tile cache, default http://localhost:8081
	CacheDir    string     // ALVYO_CACHE_DIR: rendered images etc., default <tmp>/alvyo
	PhotosDir   string     // ALVYO_PHOTOS_DIR: uploaded photos (keep and back up), default data/photos
	// SwissALTI3DDir holds swisstopo's height model as tiles
	// (infra/data-import/swissalti3d.py): ALVYO_SWISSALTI3D_DIR. Heights
	// come from there and, beyond the border or without it, from geo.admin.
	SwissALTI3DDir string
	// geo.admin's profile and identify services, replaced by a fake in the
	// end-to-end tests: ALVYO_ELEVATION_URL, ALVYO_AREAS_URL; empty for
	// geo.admin.
	ElevationURL string
	AreasURL     string
	// OJP (public transport connections): ALVYO_OJP_TOKEN is the
	// opentransportdata.swiss API key; without it the feature is off.
	OJPURL   string // ALVYO_OJP_URL, default the OJP 2.0 production endpoint
	OJPToken string
	// RelaxedLimits (ALVYO_RELAXED_LIMITS=true) lifts the per-IP signup
	// limit for end-to-end tests. Never set it in production.
	RelaxedLimits bool
	// Bug reports open issues in ALVYO_GITHUB_REPO (default tellbow/alvyo-feedback, private)
	// with ALVYO_GITHUB_TOKEN (issues and contents: write, for the screenshots);
	// without it they are only kept, without screenshot.
	GitHubRepo  string
	GitHubToken string
	SMTP        mailer.SMTPConfig
	// OIDC sign-in providers: ALVYO_OIDC_PROVIDERS lists ids (a-z, 0-9),
	// each with ALVYO_OIDC_<ID>_ISSUER, _CLIENT_ID, _CLIENT_SECRET and
	// optionally _NAME (the button label). Sign in with Apple has no fixed
	// secret: _KEY (the .p8 key, PEM), _KEY_ID and _TEAM_ID sign one, and
	// _APP_ID is the iOS app's bundle id for the app's own sign-in.
	OIDC []OIDCProvider
}

// OIDCProvider is one configured OpenID Connect provider.
type OIDCProvider struct {
	ID, Name, Issuer, ClientID, ClientSecret string
	TeamID, KeyID, Key, AppID                string
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
			ClientID: os.Getenv(env + "CLIENT_ID"), ClientSecret: os.Getenv(env + "CLIENT_SECRET"),
			TeamID: os.Getenv(env + "TEAM_ID"), KeyID: os.Getenv(env + "KEY_ID"), Key: os.Getenv(env + "KEY"),
			AppID: os.Getenv(env + "APP_ID")}
		if p.Key != "" {
			if p.Issuer == "" || p.ClientID == "" || p.TeamID == "" || p.KeyID == "" {
				return nil, fmt.Errorf("OIDC provider %s: with %sKEY, %sISSUER, %sCLIENT_ID, %sTEAM_ID and %sKEY_ID are required", id, env, env, env, env, env)
			}
			if err := checkECKey(p.Key); err != nil {
				return nil, fmt.Errorf("OIDC provider %s: %sKEY: %w", id, env, err)
			}
		} else if p.Issuer == "" || p.ClientID == "" || p.ClientSecret == "" {
			return nil, fmt.Errorf("OIDC provider %s: %sISSUER, %sCLIENT_ID and %sCLIENT_SECRET are required", id, env, env, env)
		}
		out = append(out, p)
	}
	return out, nil
}

// checkECKey fails early on a key that cannot sign client secrets.
func checkECKey(p string) error {
	block, _ := pem.Decode([]byte(p))
	if block == nil {
		return errors.New("not PEM")
	}
	k, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return err
	}
	if _, ok := k.(*ecdsa.PrivateKey); !ok {
		return errors.New("not an EC key")
	}
	return nil
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
		AdminListen:   getenv("ALVYO_ADMIN_LISTEN", ":8082"),
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
		SwissALTI3DDir: os.Getenv("ALVYO_SWISSALTI3D_DIR"),
		ElevationURL:   os.Getenv("ALVYO_ELEVATION_URL"),
		AreasURL:       os.Getenv("ALVYO_AREAS_URL"),
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
	c.AdminURL = strings.TrimSuffix(getenv("ALVYO_ADMIN_URL", c.PublicURL), "/")
	for _, j := range strings.Split(os.Getenv("ALVYO_ADMIN_JOBS"), ",") {
		if j = strings.TrimSpace(j); j != "" {
			c.AdminJobs = append(c.AdminJobs, j)
		}
	}
	return c, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
