package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tellbow/alvyo/api/internal/admin"
)

// The admin portal (feedback issues 70, 72): find people and items, act on
// them, and undo from «Verlauf».
func TestAdminPortal(t *testing.T) {
	s := newTestServer(t, Limits{})
	ctx := context.Background()
	signup := func(name, role string) *client {
		c := s.client(t)
		s.signup(c, name+"@example.ch", name)
		if _, err := s.db.Exec(ctx, `UPDATE users SET role = $2, email_verified_at = now() WHERE username = $1`, name, role); err != nil {
			t.Fatal(err)
		}
		return c
	}
	mod, adm, troll := signup("mod", "moderator"), signup("adm", "admin"), signup("troll", "user")
	m, a := s.onAdmin(mod), s.onAdmin(adm)
	_, body := troll.do("POST", "/api/v1/routes", lineRoute("Werbung", "public", 8.0, 46.6, "T2"))
	var route savedRoute
	_ = json.Unmarshal(body, &route)

	visibility := func() string {
		var v string
		if err := s.db.QueryRow(ctx, `SELECT visibility FROM routes WHERE id = $1`, route.ID).Scan(&v); err != nil {
			t.Fatal(err)
		}
		return v
	}
	var users struct {
		Users []struct {
			ID, Username, Role string
			Routes             int
		} `json:"users"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/users?q=TRO", nil)
	_ = json.Unmarshal(body, &users)
	if len(users.Users) != 1 || users.Users[0].Username != "troll" || users.Users[0].Routes != 1 {
		t.Fatalf("users: %s", body)
	}
	trollID := users.Users[0].ID

	// All accounts, by pages of 50, with the totals.
	var all struct {
		Users  []struct{ Username string } `json:"users"`
		Counts struct{ Total, Banned int } `json:"counts"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/users", nil)
	_ = json.Unmarshal(body, &all)
	if len(all.Users) != 3 || all.Users[0].Username != "troll" || all.Counts.Total != 3 || all.Counts.Banned != 0 {
		t.Errorf("all users: %s", body)
	}
	_, body = m.do("GET", "/admin-api/v1/admin/users?page=2", nil)
	_ = json.Unmarshal(body, &all)
	if len(all.Users) != 0 || all.Counts.Total != 3 {
		t.Errorf("page 2: %s", body)
	}
	if code, _ := mod.do("GET", "/api/v1/admin/users", nil); code != http.StatusNotFound {
		t.Errorf("admin users on the public API: %d, want 404", code)
	}
	if code, _ := s.onAdmin(troll).do("GET", "/admin-api/v1/admin/users", nil); code != http.StatusForbidden {
		t.Errorf("a user lists users: %d, want 403", code)
	}

	// Banning makes the route private; undo shares it again.
	var done struct {
		LogID string `json:"log_id"`
	}
	code, body := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/ban", nil)
	_ = json.Unmarshal(body, &done)
	if code != http.StatusOK || visibility() != "private" {
		t.Fatalf("ban: %d %s, route %s", code, body, visibility())
	}
	if code, _ := troll.do("GET", "/api/v1/me", nil); code != http.StatusUnauthorized {
		t.Errorf("banned troll still logged in: %d", code)
	}
	_, body = m.do("GET", "/admin-api/v1/admin/users", nil)
	_ = json.Unmarshal(body, &all)
	if all.Counts.Banned != 1 {
		t.Errorf("banned: %s", body)
	}
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/ban", nil); code != http.StatusConflict {
		t.Errorf("ban twice: %d, want 409", code)
	}
	if code, body := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusNoContent {
		t.Fatalf("undo ban: %d %s", code, body)
	}
	if visibility() != "public" {
		t.Errorf("after undoing the ban: %s", visibility())
	}
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusConflict {
		t.Errorf("undo twice: %d, want 409", code)
	}

	// Staff is not banned; roles are the admins'.
	var admID string
	_ = s.db.QueryRow(ctx, `SELECT id FROM users WHERE username = 'adm'`).Scan(&admID)
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+admID+"/ban", nil); code != http.StatusForbidden {
		t.Errorf("ban an admin: %d, want 403", code)
	}
	if code, _ := m.do("PUT", "/admin-api/v1/admin/users/"+trollID+"/role", map[string]any{"role": "moderator"}); code != http.StatusForbidden {
		t.Errorf("moderator sets a role: %d, want 403", code)
	}
	if code, _ := a.do("PUT", "/admin-api/v1/admin/users/"+admID+"/role", map[string]any{"role": "user"}); code != http.StatusUnprocessableEntity {
		t.Errorf("admin demotes themselves: %d, want 422", code)
	}
	_, body = a.do("PUT", "/admin-api/v1/admin/users/"+trollID+"/role", map[string]any{"role": "moderator"})
	_ = json.Unmarshal(body, &done)
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusForbidden {
		t.Errorf("moderator undoes a role: %d, want 403", code)
	}
	if code, _ := a.do("POST", "/admin-api/v1/admin/log/"+done.LogID+"/undo", nil); code != http.StatusNoContent {
		t.Errorf("admin undoes a role: %d", code)
	}

	// Items by link; unpublishing, and an undo refused after a later change.
	var items struct {
		Items []struct{ Kind, ID, Owner, Visibility string } `json:"items"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/items?q=https://alvyo.tellbow.ch/routes/"+route.ID, nil)
	_ = json.Unmarshal(body, &items)
	if len(items.Items) != 1 || items.Items[0].Owner != "troll" || items.Items[0].Visibility != "public" {
		t.Fatalf("items: %s", body)
	}
	_, body = m.do("POST", "/admin-api/v1/admin/items/route/"+route.ID+"/unpublish", nil)
	var unpublished struct {
		LogID string `json:"log_id"`
	}
	_ = json.Unmarshal(body, &unpublished)
	if visibility() != "private" {
		t.Fatalf("unpublish: %s", body)
	}
	if _, err := s.db.Exec(ctx, `UPDATE routes SET visibility = 'public' WHERE id = $1`, route.ID); err != nil {
		t.Fatal(err)
	}
	_, body = m.do("POST", "/admin-api/v1/admin/items/route/"+route.ID+"/unpublish", nil)
	_ = json.Unmarshal(body, &done)
	if code, _ := m.do("POST", "/admin-api/v1/admin/log/"+unpublished.LogID+"/undo", nil); code != http.StatusConflict {
		t.Errorf("undo before a later change: %d, want 409", code)
	}

	// A new confirmation e-mail only for an address not confirmed.
	if code, _ := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/verification", nil); code != http.StatusConflict {
		t.Errorf("verification when confirmed: %d, want 409", code)
	}
	if _, err := s.db.Exec(ctx, `UPDATE users SET email_verified_at = NULL WHERE username = 'troll'`); err != nil {
		t.Fatal(err)
	}
	sent := len(s.mail.Sent())
	if code, body := m.do("POST", "/admin-api/v1/admin/users/"+trollID+"/verification", nil); code != http.StatusOK || len(s.mail.Sent()) != sent+1 {
		t.Errorf("verification: %d %s", code, body)
	}

	// «Verlauf»: newest first, by area.
	var log struct {
		Entries []struct {
			Title    string
			Undoable bool
			UndoneAt *string `json:"undone_at"`
		} `json:"entries"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/log?area=nutzer", nil)
	_ = json.Unmarshal(body, &log)
	var titles []string
	for _, e := range log.Entries {
		titles = append(titles, e.Title)
	}
	if got := strings.Join(titles, " | "); got != "Bestätigungs-E-Mail an @troll | @troll: Rolle user → moderator | @troll gesperrt" {
		t.Errorf("log: %s", got)
	}
	if len(log.Entries) == 3 && (log.Entries[2].UndoneAt == nil || log.Entries[2].Undoable) {
		t.Errorf("the undone ban: %s", body)
	}
}

// «System» checks the outside services and says how fresh the data is;
// «Statistik» counts people, not the system's own accounts.
func TestAdminSystemAndStats(t *testing.T) {
	up := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	t.Cleanup(up.Close)
	broken := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	t.Cleanup(broken.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Admin.Probes = []admin.Probe{{Name: "up", URL: up.URL}, {Name: "broken", URL: broken.URL}, {Name: "closed", URL: "tcp://127.0.0.1:1"}}
		d.Admin.GraphHopper = up.URL // answers no /info
	})
	ctx := context.Background()
	mod := s.client(t)
	s.signup(mod, "mod@example.ch", "mod")
	if _, err := s.db.Exec(ctx, `UPDATE users SET role = 'moderator', email_verified_at = now() WHERE username = 'mod'`); err != nil {
		t.Fatal(err)
	}
	m := s.onAdmin(mod)
	mod.do("POST", "/api/v1/routes", lineRoute("Gipfel", "public", 8.0, 46.6, "T2"))

	var sys struct {
		Services []struct {
			Name string
			Up   bool
		} `json:"services"`
		Data []struct {
			Name  string
			Stale bool
			Count *int64
		} `json:"data"`
		Migration int64  `json:"migration"`
		Version   string `json:"version"`
	}
	code, body := m.do("GET", "/admin-api/v1/admin/system", nil)
	_ = json.Unmarshal(body, &sys)
	if code != http.StatusOK || len(sys.Services) != 3 || !sys.Services[0].Up || sys.Services[1].Up || sys.Services[2].Up {
		t.Fatalf("services: %d %s", code, body)
	}
	if sys.Migration < 45 || sys.Version != "test" || len(sys.Data) == 0 || !sys.Data[0].Stale {
		t.Errorf("system: %s", body)
	}

	var st struct {
		Totals struct {
			Accounts, Routes int
			Active7          int `json:"active_7"`
		} `json:"totals"`
		Weeks []struct{ Accounts, Routes int } `json:"weeks"`
	}
	_, body = m.do("GET", "/admin-api/v1/admin/stats", nil)
	_ = json.Unmarshal(body, &st)
	// A session just started counts as active (last_seen_at is written a day later).
	if st.Totals.Accounts != 1 || st.Totals.Routes != 1 || st.Totals.Active7 != 1 || len(st.Weeks) != 12 || st.Weeks[0].Accounts != 1 || st.Weeks[0].Routes != 1 {
		t.Errorf("stats: %s", body)
	}
	if code, _ := s.client(t).do("GET", "/api/v1/admin/stats", nil); code != http.StatusNotFound {
		t.Errorf("stats on the public API: %d, want 404", code)
	}
}

// Cron jobs started by hand from «System»: only the allowed ones, by
// admins, built from the cron job's template.
func TestAdminJobs(t *testing.T) {
	const cron = `{"metadata": {"name": "%s", "uid": "0199a000-0000-7000-8000-0000000000%s"},
		"spec": {"schedule": "*/5 * * * *", "jobTemplate": {"metadata": {"labels": {"app": "%s"}},
			"spec": {"backoffLimit": 1, "template": {"spec": {"containers": [{"name": "run", "image": "ghcr.io/tellbow/alvyo-data-import:1"}]}}}}},
		"status": {"lastScheduleTime": "2026-10-30T10:00:00Z", "lastSuccessfulTime": "2026-10-30T10:01:00Z"}}`
	var posted []byte
	var auth string
	kube := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		switch r.Method + " " + r.URL.Path {
		case "GET /apis/batch/v1/namespaces/alvyo/cronjobs":
			_, _ = fmt.Fprintf(w, `{"items": [`+cron+`, `+cron+`, `+cron+`]}`,
				"db-backup", "01", "db-backup", "graph-refresh", "02", "graph-refresh", "weather-precip", "03", "weather-precip")
		case "GET /apis/batch/v1/namespaces/alvyo/cronjobs/weather-precip":
			_, _ = fmt.Fprintf(w, cron, "weather-precip", "03", "weather-precip")
		case "POST /apis/batch/v1/namespaces/alvyo/jobs":
			posted, _ = io.ReadAll(r.Body)
			_, _ = w.Write([]byte(`{"metadata": {"name": "weather-precip-manual-x"}}`))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(kube.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Admin.Kube = &admin.Kube{URL: kube.URL, Namespace: "alvyo", Client: kube.Client(),
			Token: func() (string, error) { return "sa-token", nil }, Allowed: []string{"weather-precip", "graph-refresh"}}
	})
	ctx := context.Background()
	mod, adm := s.client(t), s.client(t)
	s.signup(mod, "mod@example.ch", "mod")
	s.signup(adm, "adm@example.ch", "adm")
	if _, err := s.db.Exec(ctx, `UPDATE users SET role = CASE username WHEN 'mod' THEN 'moderator' ELSE 'admin' END`); err != nil {
		t.Fatal(err)
	}
	m, a := s.onAdmin(mod), s.onAdmin(adm)

	var jobs struct {
		Available bool
		Jobs      []struct {
			Name         string
			LastFinished bool `json:"last_finished"`
		}
	}
	_, body := m.do("GET", "/admin-api/v1/admin/jobs", nil)
	_ = json.Unmarshal(body, &jobs)
	if !jobs.Available || len(jobs.Jobs) != 2 || jobs.Jobs[0].Name != "weather-precip" || jobs.Jobs[1].Name != "graph-refresh" ||
		!jobs.Jobs[0].LastFinished || auth != "Bearer sa-token" {
		t.Fatalf("jobs: %s (auth %q)", body, auth)
	}
	if code, _ := m.do("POST", "/admin-api/v1/admin/jobs/weather-precip/run", nil); code != http.StatusForbidden {
		t.Errorf("moderator runs a job: %d, want 403", code)
	}
	if code, _ := a.do("POST", "/admin-api/v1/admin/jobs/db-backup/run", nil); code != http.StatusNotFound || posted != nil {
		t.Errorf("a job not allowed: %d", code)
	}
	code, body := a.do("POST", "/admin-api/v1/admin/jobs/weather-precip/run", nil)
	if code != http.StatusOK || !strings.Contains(string(body), `"job":"weather-precip-manual-x"`) {
		t.Fatalf("run: %d %s", code, body)
	}
	var job struct {
		Metadata struct {
			Name            string
			Labels          map[string]string
			Annotations     map[string]string
			OwnerReferences []struct{ Kind, Name, UID string } `json:"ownerReferences"`
		}
		Spec struct {
			BackoffLimit int `json:"backoffLimit"`
		}
	}
	_ = json.Unmarshal(posted, &job)
	if !strings.HasPrefix(job.Metadata.Name, "weather-precip-manual-") || job.Metadata.Labels["app"] != "weather-precip" ||
		job.Metadata.Annotations["cronjob.kubernetes.io/instantiate"] != "manual" || len(job.Metadata.OwnerReferences) != 1 ||
		job.Metadata.OwnerReferences[0].Kind != "CronJob" || job.Metadata.OwnerReferences[0].UID != "0199a000-0000-7000-8000-000000000003" ||
		job.Spec.BackoffLimit != 1 {
		t.Errorf("job: %s", posted)
	}
	if _, body := a.do("GET", "/admin-api/v1/admin/log?area=system", nil); !strings.Contains(string(body), "weather-precip von Hand gestartet") {
		t.Errorf("log: %s", body)
	}
}
