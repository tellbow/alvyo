package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testConfigMap = `apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
data:
  ALVYO_SMTP_PORT: "587"
  ALVYO_OIDC_PROVIDERS: "apple"
  ALVYO_OIDC_APPLE_ISSUER: https://appleid.apple.com
  ALVYO_OIDC_APPLE_CLIENT_ID: ch.tellbow.alvyo
  ALVYO_OIDC_APPLE_TEAM_ID: TEAM
  ALVYO_OIDC_APPLE_KEY_ID: KEY
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-config
data:
  OTHER: "1"
`

const testDeployment = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    spec:
      initContainers:
        - name: migrate
          env:
            - name: ALVYO_DATABASE_URL
              valueFrom:
                secretKeyRef: {name: alvyo-secret, key: ALVYO_DATABASE_URL}
      containers:
        - name: api
          envFrom:
            - configMapRef: {name: api-config}
          env:
            - name: ALVYO_DATABASE_URL
              valueFrom:
                secretKeyRef: {name: alvyo-secret, key: ALVYO_DATABASE_URL}
            - name: ALVYO_OIDC_APPLE_KEY
              valueFrom:
                secretKeyRef: {name: alvyo-secret, key: ALVYO_OIDC_APPLE_KEY}
`

func TestCheckDeployment(t *testing.T) {
	saved := os.Environ()
	t.Cleanup(func() {
		os.Clearenv()
		for _, kv := range saved {
			k, v, _ := strings.Cut(kv, "=")
			_ = os.Setenv(k, v)
		}
	})
	check := func(configMap, deployment string) error {
		dir := t.TempDir()
		for name, content := range map[string]string{"configmap.yaml": configMap, "api-deployment.yaml": deployment} {
			if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		return checkDeployment(dir)
	}

	if err := check(testConfigMap, testDeployment); err != nil {
		t.Errorf("a good deployment: %v", err)
	}
	for _, c := range []struct {
		name, configMap, deployment, want, where string
	}{
		// 2026-10-19: Apple's key was in the secret but not passed to the API.
		{"a sign-in key not passed on", testConfigMap, strings.Replace(testDeployment, `- name: ALVYO_OIDC_APPLE_KEY
              valueFrom:
                secretKeyRef: {name: alvyo-secret, key: ALVYO_OIDC_APPLE_KEY}
`, "", 1), "ALVYO_OIDC_APPLE", "container api"},
		{"no database in the init container", testConfigMap, strings.Replace(testDeployment, `        - name: migrate
          env:
            - name: ALVYO_DATABASE_URL
              valueFrom:
                secretKeyRef: {name: alvyo-secret, key: ALVYO_DATABASE_URL}
`, "        - name: migrate\n", 1), "ALVYO_DATABASE_URL", "container migrate"},
		{"a bad port", strings.Replace(testConfigMap, `"587"`, `"smtp"`, 1), testDeployment, "ALVYO_SMTP_PORT", "container api"},
		{"a missing ConfigMap", strings.Replace(testConfigMap, "name: api-config", "name: renamed", 1), testDeployment, "no ConfigMap api-config", "container api"},
	} {
		err := check(c.configMap, c.deployment)
		if err == nil || !strings.Contains(err.Error(), c.want) || !strings.Contains(err.Error(), c.where) {
			t.Errorf("%s: %v", c.name, err)
		}
	}
	if err := check(testConfigMap, "kind: Service\n"); err == nil {
		t.Error("no container at all passed")
	}
}
