package admin

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrJob means the cron job is not one the portal may run.
var ErrJob = errors.New("not a job the admin portal runs")

// Kube lists the namespace's cron jobs and starts one of them now, as
// `kubectl create job --from=cronjob/…` does, through the Kubernetes API
// with the pod's service account. A ValidatingAdmissionPolicy in the
// cluster limits what Jobs that account may create.
type Kube struct {
	URL       string // the Kubernetes API
	Namespace string
	Token     func() (string, error)
	Client    *http.Client
	Allowed   []string // the cron jobs the portal shows and runs, in this order
}

const serviceAccount = "/var/run/secrets/kubernetes.io/serviceaccount"

// InCluster sets up Kube from the pod's service account; nil outside a
// cluster or without allowed jobs.
func InCluster(allowed []string) (*Kube, error) {
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || len(allowed) == 0 {
		return nil, nil
	}
	ca, err := os.ReadFile(serviceAccount + "/ca.crt")
	if err != nil {
		return nil, fmt.Errorf("admin jobs: %w (is the service account token mounted?)", err)
	}
	ns, err := os.ReadFile(serviceAccount + "/namespace")
	if err != nil {
		return nil, fmt.Errorf("admin jobs: %w", err)
	}
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(ca)
	return &Kube{
		URL:       "https://" + net.JoinHostPort(host, port),
		Namespace: strings.TrimSpace(string(ns)),
		// Read each time: the kubelet rotates it.
		Token: func() (string, error) {
			b, err := os.ReadFile(serviceAccount + "/token")
			return strings.TrimSpace(string(b)), err
		},
		Client:  &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}},
		Allowed: allowed,
	}, nil
}

func (k *Kube) do(ctx context.Context, method, path string, body, out any) error {
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		r = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, k.URL+path, r)
	if err != nil {
		return err
	}
	token, err := k.Token()
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := k.Client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("kubernetes %s %s: %s %s", method, path, resp.Status, msg)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// cronJob is the part of a CronJob that is read.
type cronJob struct {
	Metadata struct {
		Name string `json:"name"`
		UID  string `json:"uid"`
	} `json:"metadata"`
	Spec struct {
		Schedule    string `json:"schedule"`
		Suspend     bool   `json:"suspend"`
		JobTemplate struct {
			Metadata struct {
				Labels      map[string]string `json:"labels"`
				Annotations map[string]string `json:"annotations"`
			} `json:"metadata"`
			Spec json.RawMessage `json:"spec"`
		} `json:"jobTemplate"`
	} `json:"spec"`
	Status struct {
		Active             []json.RawMessage `json:"active"`
		LastScheduleTime   *time.Time        `json:"lastScheduleTime"`
		LastSuccessfulTime *time.Time        `json:"lastSuccessfulTime"`
	} `json:"status"`
}

// CronJob is a job as «System» shows it.
type CronJob struct {
	Name         string     `json:"name"`
	Schedule     string     `json:"schedule"`
	Suspended    bool       `json:"suspended" doc:"Runs only when started by hand"`
	Running      bool       `json:"running"`
	LastStart    *time.Time `json:"last_start,omitempty"`
	LastSuccess  *time.Time `json:"last_success,omitempty"`
	LastFinished bool       `json:"last_finished" doc:"The last start ended well"`
}

// CronJobs lists the allowed cron jobs, in their order.
func (k *Kube) CronJobs(ctx context.Context) ([]CronJob, error) {
	var list struct {
		Items []cronJob `json:"items"`
	}
	if err := k.do(ctx, http.MethodGet, "/apis/batch/v1/namespaces/"+k.Namespace+"/cronjobs", nil, &list); err != nil {
		return nil, err
	}
	out := []CronJob{}
	for _, name := range k.Allowed {
		i := slices.IndexFunc(list.Items, func(c cronJob) bool { return c.Metadata.Name == name })
		if i < 0 {
			continue
		}
		c := list.Items[i]
		j := CronJob{Name: name, Schedule: c.Spec.Schedule, Suspended: c.Spec.Suspend, Running: len(c.Status.Active) > 0,
			LastStart: c.Status.LastScheduleTime, LastSuccess: c.Status.LastSuccessfulTime}
		j.LastFinished = j.LastSuccess != nil && (j.LastStart == nil || !j.LastSuccess.Before(*j.LastStart))
		out = append(out, j)
	}
	return out, nil
}

// Run starts the cron job name now and returns the Job's name and the cron
// job's uid.
func (k *Kube) Run(ctx context.Context, name string) (string, uuid.UUID, error) {
	if !slices.Contains(k.Allowed, name) {
		return "", uuid.Nil, ErrJob
	}
	var c cronJob
	if err := k.do(ctx, http.MethodGet, "/apis/batch/v1/namespaces/"+k.Namespace+"/cronjobs/"+name, nil, &c); err != nil {
		return "", uuid.Nil, err
	}
	uid, err := uuid.Parse(c.Metadata.UID)
	if err != nil {
		return "", uuid.Nil, err
	}
	annotations := map[string]string{"cronjob.kubernetes.io/instantiate": "manual"}
	for key, v := range c.Spec.JobTemplate.Metadata.Annotations {
		annotations[key] = v
	}
	job := map[string]any{
		"apiVersion": "batch/v1",
		"kind":       "Job",
		"metadata": map[string]any{
			"name":        name + "-manual-" + strconv.FormatInt(time.Now().Unix(), 36),
			"labels":      c.Spec.JobTemplate.Metadata.Labels,
			"annotations": annotations,
			"ownerReferences": []map[string]any{{
				"apiVersion": "batch/v1", "kind": "CronJob", "name": name, "uid": c.Metadata.UID, "controller": true,
			}},
		},
		"spec": c.Spec.JobTemplate.Spec,
	}
	var created struct {
		Metadata struct {
			Name string `json:"name"`
		} `json:"metadata"`
	}
	if err := k.do(ctx, http.MethodPost, "/apis/batch/v1/namespaces/"+k.Namespace+"/jobs", job, &created); err != nil {
		return "", uuid.Nil, err
	}
	return created.Metadata.Name, uid, nil
}

// RunLogged starts the cron job name (see Run) and logs it for «Verlauf».
func (s *Store) RunLogged(ctx context.Context, actor uuid.UUID, name string) (string, uuid.UUID, error) {
	if s.Kube == nil {
		return "", uuid.Nil, ErrJob
	}
	job, uid, err := s.Kube.Run(ctx, name)
	if err != nil {
		return "", uuid.Nil, err
	}
	id, err := s.do(ctx, actor, func(pgx.Tx) (Entry, error) {
		return Entry{Area: "system", Title: name + " von Hand gestartet (" + job + ")", TargetKind: "job", TargetID: uid}, nil
	})
	return job, id, err
}
