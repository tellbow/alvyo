package config

import (
	"log/slog"
	"strings"
	"testing"
)

func TestFromEnv(t *testing.T) {
	t.Setenv("ALVYO_DATABASE_URL", "")
	if _, err := FromEnv(); err == nil || !strings.Contains(err.Error(), "ALVYO_DATABASE_URL") {
		t.Errorf("without a database: %v", err)
	}

	t.Setenv("ALVYO_DATABASE_URL", "postgres://db/alvyo")
	t.Setenv("ALVYO_PUBLIC_URL", "https://alvyo.example/")
	c, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if c.Listen != ":8080" || c.PublicURL != "https://alvyo.example" || c.LogLevel != slog.LevelInfo ||
		c.SMTP.Port != 1025 || c.SMTP.TLS != "none" || c.TrustProxy || c.RelaxedLimits || len(c.OIDC) != 0 {
		t.Errorf("defaults: %+v", c)
	}

	for _, bad := range []struct{ key, value, want string }{
		{"ALVYO_SMTP_PORT", "25x", "ALVYO_SMTP_PORT"},
		{"ALVYO_LOG_LEVEL", "loud", "loud"},
		{"ALVYO_OIDC_PROVIDERS", "Google", "a-z and 0-9"},
		{"ALVYO_OIDC_PROVIDERS", "google", "ALVYO_OIDC_GOOGLE_CLIENT_SECRET"},
	} {
		t.Run(bad.key+"="+bad.value, func(t *testing.T) {
			t.Setenv(bad.key, bad.value)
			if _, err := FromEnv(); err == nil || !strings.Contains(err.Error(), bad.want) {
				t.Errorf("err = %v, want it to mention %q", err, bad.want)
			}
		})
	}
}

func TestOIDCProviders(t *testing.T) {
	t.Setenv("ALVYO_DATABASE_URL", "postgres://db/alvyo")
	t.Setenv("ALVYO_OIDC_PROVIDERS", " google , ,swisspass")
	for _, id := range []string{"GOOGLE", "SWISSPASS"} {
		t.Setenv("ALVYO_OIDC_"+id+"_ISSUER", "https://"+id+".example")
		t.Setenv("ALVYO_OIDC_"+id+"_CLIENT_ID", "client-"+id)
		t.Setenv("ALVYO_OIDC_"+id+"_CLIENT_SECRET", "not-a-secret")
	}
	t.Setenv("ALVYO_OIDC_SWISSPASS_NAME", "SwissPass")
	c, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if len(c.OIDC) != 2 || c.OIDC[0].ID != "google" || c.OIDC[0].Name != "google" ||
		c.OIDC[1].Name != "SwissPass" || c.OIDC[1].ClientID != "client-SWISSPASS" {
		t.Errorf("providers: %+v", c.OIDC)
	}
}
