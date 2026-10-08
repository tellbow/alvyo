package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

// hikeBody is a recorded hike 2 km east from lon0 at 46.5° N, a position
// every 20 m and minute.
func hikeBody(id, routeID string, lon0 float64, start time.Time) map[string]any {
	var pts []map[string]any
	for i := range 100 {
		pts = append(pts, map[string]any{"lon": lon0 + float64(i)*20/76_600, "lat": 46.5, "t": start.Add(time.Duration(i) * time.Minute)})
	}
	return map[string]any{"id": id, "route_id": routeID, "title": "Gratweg, 23.09.2026", "points": pts}
}

type hikeResp struct {
	ID         string `json:"id"`
	Title      string `json:"title"`
	Visibility string `json:"visibility"`
	Totals     struct {
		DistanceM float64 `json:"distance_m"`
	} `json:"totals"`
	Hike *struct {
		At             time.Time `json:"at"`
		DurationS      int       `json:"duration_s"`
		PlannedRouteID string    `json:"planned_route_id"`
	} `json:"hike"`
}

func TestUploadHike(t *testing.T) {
	s := newImportServer(t, "")
	c := s.client(t)
	start := time.Date(2026, 9, 23, 8, 0, 0, 0, time.UTC)
	if code, _ := c.do("POST", "/api/v1/hikes", hikeBody("rec-1", "", 8.0, start)); code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", code)
	}
	s.signup(c, "hiker@example.ch", "hiker")
	_, body := c.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var planned savedRoute
	_ = json.Unmarshal(body, &planned)

	code, body := c.do("POST", "/api/v1/hikes", hikeBody("rec-1", planned.ID, 8.0, start))
	var up struct{ ID string }
	if err := json.Unmarshal(body, &up); code != http.StatusCreated || err != nil {
		t.Fatalf("upload: %d %s", code, body)
	}
	_, body = c.do("GET", "/api/v1/routes/"+up.ID, nil)
	var r hikeResp
	_ = json.Unmarshal(body, &r)
	if r.Hike == nil || !r.Hike.At.Equal(start) || r.Hike.DurationS != 99*60 || r.Hike.PlannedRouteID != planned.ID {
		t.Fatalf("hike: %s", body)
	}
	if r.Visibility != "private" || r.Title != "Gratweg, 23.09.2026" || r.Totals.DistanceM < 1900 || r.Totals.DistanceM > 2100 {
		t.Errorf("route: %s", body)
	}

	// The first upload saved the route but not that it was hiked: the
	// upload again does (else it would be shown without privacy zones).
	if _, err := s.db.Exec(context.Background(), `UPDATE routes SET hiked_at = NULL WHERE id = $1`, up.ID); err != nil {
		t.Fatal(err)
	}

	// The app uploads again (no answer the first time): the same route.
	code, body = c.do("POST", "/api/v1/hikes", hikeBody("rec-1", planned.ID, 8.0, start))
	var again struct{ ID string }
	_ = json.Unmarshal(body, &again)
	if code != http.StatusOK || again.ID != up.ID {
		t.Errorf("again: %d %s", code, body)
	}
	_, body = c.do("GET", "/api/v1/routes/"+up.ID, nil)
	r = hikeResp{}
	_ = json.Unmarshal(body, &r)
	if r.Hike == nil || !r.Hike.At.Equal(start) {
		t.Errorf("again: not marked as hiked: %s", body)
	}
	_, body = c.do("GET", "/api/v1/routes", nil)
	var list struct {
		Routes []hikeResp `json:"routes"`
	}
	_ = json.Unmarshal(body, &list)
	if len(list.Routes) != 2 || (list.Routes[0].Hike == nil) == (list.Routes[1].Hike == nil) { // before the long one
		t.Errorf("list: %s", body)
	}

	// A long hike recorded every second (the Watch): over the default 1 MB.
	long := hikeBody("rec-long", "", 8.0, start)
	var many []map[string]any
	for i := range 20_000 {
		many = append(many, map[string]any{"lon": 8.0 + float64(i%2000)*1.3/76_600, "lat": 46.5 + float64(i/2000)*0.0001, "t": start.Add(time.Duration(i) * time.Second)})
	}
	long["points"] = many
	if code, body := c.do("POST", "/api/v1/hikes", long); code != http.StatusCreated {
		t.Errorf("long hike: %d %.200s", code, body)
	}

	if code, body := c.do("POST", "/api/v1/hikes", hikeBody("rec-2", "", 2.3, start)); code != http.StatusUnprocessableEntity {
		t.Errorf("outside: %d %s", code, body)
	}

	// Someone else's private route is not linked.
	other := s.client(t)
	s.signup(other, "other@example.ch", "other")
	code, body = other.do("POST", "/api/v1/hikes", hikeBody("rec-1", planned.ID, 8.0, start))
	_ = json.Unmarshal(body, &up)
	_, body = other.do("GET", "/api/v1/routes/"+up.ID, nil)
	var theirs hikeResp
	_ = json.Unmarshal(body, &theirs)
	if code != http.StatusCreated || theirs.Hike == nil || theirs.Hike.PlannedRouteID != "" {
		t.Errorf("other's hike: %d %s", code, body)
	}
}
