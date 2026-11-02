package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"go.yaml.in/yaml/v3"

	"github.com/tellbow/alvyo/api/internal/config"
	"github.com/tellbow/alvyo/api/internal/mailer"
)

type k8sContainer struct {
	Name    string `yaml:"name"`
	EnvFrom []struct {
		ConfigMapRef *struct {
			Name string `yaml:"name"`
		} `yaml:"configMapRef"`
	} `yaml:"envFrom"`
	Env []struct {
		Name      string `yaml:"name"`
		Value     string `yaml:"value"`
		ValueFrom *struct {
			ConfigMapKeyRef *struct {
				Name     string `yaml:"name"`
				Key      string `yaml:"key"`
				Optional bool   `yaml:"optional"`
			} `yaml:"configMapKeyRef"`
			SecretKeyRef *struct {
				Key string `yaml:"key"`
			} `yaml:"secretKeyRef"`
		} `yaml:"valueFrom"`
	} `yaml:"env"`
}

type k8sManifest struct {
	Kind     string `yaml:"kind"`
	Metadata struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Data map[string]string `yaml:"data"`
	Spec struct {
		Template struct {
			Spec struct {
				InitContainers []k8sContainer `yaml:"initContainers"`
				Containers     []k8sContainer `yaml:"containers"`
			} `yaml:"spec"`
		} `yaml:"template"`
	} `yaml:"spec"`
}

func readManifests(path string) ([]k8sManifest, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []k8sManifest
	dec := yaml.NewDecoder(bytes.NewReader(raw))
	for {
		var m k8sManifest
		switch err := dec.Decode(&m); {
		case errors.Is(err, io.EOF):
			return out, nil
		case err != nil:
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		out = append(out, m)
	}
}

// checkDeployment loads the configuration as each container of the API's
// deployment would get it, so that what stops a new pod shows before a release:
// with `strategy: Recreate` the old pod is gone by then. The secret is not read:
// a value it maps counts as set (a key missing there is not found here).
func checkDeployment(dir string) error {
	deployment, err := readManifests(filepath.Join(dir, "api-deployment.yaml"))
	if err != nil {
		return err
	}
	configs, err := readManifests(filepath.Join(dir, "configmap.yaml"))
	if err != nil {
		return err
	}
	maps := map[string]map[string]string{}
	for _, m := range configs {
		if m.Kind == "ConfigMap" {
			maps[m.Metadata.Name] = m.Data
		}
	}
	placeholder, err := secretPlaceholder()
	if err != nil {
		return err
	}
	checked := 0
	for _, m := range deployment {
		if m.Kind != "Deployment" {
			continue
		}
		for _, c := range append(m.Spec.Template.Spec.InitContainers, m.Spec.Template.Spec.Containers...) {
			env, err := containerEnv(c, maps, placeholder)
			if err == nil {
				err = checkEnv(env)
			}
			if err != nil {
				return fmt.Errorf("container %s: %w", c.Name, err)
			}
			checked++
		}
	}
	if checked == 0 {
		return errors.New("no container in api-deployment.yaml")
	}
	fmt.Printf("configuration of %d containers is fine\n", checked)
	return nil
}

func containerEnv(c k8sContainer, maps map[string]map[string]string, placeholder string) (map[string]string, error) {
	env := map[string]string{}
	for _, from := range c.EnvFrom {
		if from.ConfigMapRef == nil {
			continue
		}
		data, ok := maps[from.ConfigMapRef.Name]
		if !ok {
			return nil, fmt.Errorf("no ConfigMap %s", from.ConfigMapRef.Name)
		}
		for k, v := range data {
			env[k] = v
		}
	}
	for _, e := range c.Env {
		switch {
		case e.ValueFrom == nil:
			env[e.Name] = e.Value
		case e.ValueFrom.SecretKeyRef != nil:
			env[e.Name] = placeholder
		case e.ValueFrom.ConfigMapKeyRef != nil:
			r := e.ValueFrom.ConfigMapKeyRef
			v, ok := maps[r.Name][r.Key]
			if !ok && !r.Optional {
				return nil, fmt.Errorf("%s: no key %s in ConfigMap %s", e.Name, r.Key, r.Name)
			}
			env[e.Name] = v
		}
	}
	return env, nil
}

// checkEnv does what starting does with the environment, and nothing that needs
// the network.
func checkEnv(env map[string]string) error {
	os.Clearenv()
	for k, v := range env {
		if err := os.Setenv(k, v); err != nil {
			return err
		}
	}
	cfg, err := config.FromEnv()
	if err != nil {
		return err
	}
	_, err = mailer.NewSMTP(cfg.SMTP)
	return err
}

// secretPlaceholder stands in for every value from the secret: a throwaway EC
// key, since the sign-in keys are checked to be one and the others only set.
func secretPlaceholder() (string, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return "", err
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return "", err
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})), nil
}
