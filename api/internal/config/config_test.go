package config

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
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

func TestAppleProvider(t *testing.T) {
	t.Setenv("ALVYO_DATABASE_URL", "postgres://db/alvyo")
	t.Setenv("ALVYO_OIDC_PROVIDERS", "apple")
	t.Setenv("ALVYO_OIDC_APPLE_ISSUER", "https://appleid.apple.com")
	t.Setenv("ALVYO_OIDC_APPLE_CLIENT_ID", "ch.example.web")
	t.Setenv("ALVYO_OIDC_APPLE_KEY_ID", "KEY123")
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	t.Setenv("ALVYO_OIDC_APPLE_KEY", string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})))
	if _, err := FromEnv(); err == nil || !strings.Contains(err.Error(), "TEAM_ID") {
		t.Errorf("without a team: %v", err)
	}
	// No client secret: the key signs one.
	t.Setenv("ALVYO_OIDC_APPLE_TEAM_ID", "TEAM123")
	c, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if p := c.OIDC[0]; p.TeamID != "TEAM123" || p.KeyID != "KEY123" || p.ClientSecret != "" {
		t.Errorf("apple: %+v", p)
	}
	t.Setenv("ALVYO_OIDC_APPLE_KEY", "not a key")
	if _, err := FromEnv(); err == nil || !strings.Contains(err.Error(), "ALVYO_OIDC_APPLE_KEY") {
		t.Errorf("a broken key: %v", err)
	}
}
