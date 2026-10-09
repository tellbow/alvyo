package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/tellbow/alvyo/api/internal/areas"
	"github.com/tellbow/alvyo/api/internal/routing"
)

// newMCPServer is the test server with GraphHopper (the recorded First →
// Bachalpsee route for every route, three areas for every isochrone),
// geo.admin's protected areas, and two places to find.
func newMCPServer(t *testing.T) *testServer {
	t.Helper()
	route, err := os.ReadFile("../routing/testdata/gh_first_bachalpsee.json")
	if err != nil {
		t.Fatal(err)
	}
	identify, err := os.ReadFile("../areas/testdata/identify_grindelwald.json")
	if err != nil {
		t.Fatal(err)
	}
	gh := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/isochrone") {
			_, _ = w.Write([]byte(`{"polygons":[
				{"properties":{"bucket":0},"geometry":{"coordinates":[[[8.04,46.65],[8.06,46.65],[8.05,46.67],[8.04,46.65]]]}},
				{"properties":{"bucket":1},"geometry":{"coordinates":[[[8.03,46.64],[8.07,46.64],[8.05,46.68],[8.03,46.64]]]}},
				{"properties":{"bucket":2},"geometry":{"coordinates":[[[8.02,46.63],[8.08,46.63],[8.05,46.69],[8.02,46.63]]]}},
				{"properties":{"bucket":3},"geometry":{"coordinates":[[[8.01,46.62],[8.09,46.62],[8.05,46.70],[8.01,46.62]]]}}]}`))
			return
		}
		_, _ = w.Write(route)
	}))
	t.Cleanup(gh.Close)
	geoadmin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write(identify) }))
	t.Cleanup(geoadmin.Close)
	s := newTestServerWith(t, func(d *Deps) {
		d.Router = &routing.Router{
			GraphHopper: &routing.GraphHopper{URL: gh.URL},
			Elevation:   flatSampler{},
			Trails:      &routing.TrailMatcher{DB: d.DB},
			Outlines:    &routing.Outliner{DB: d.DB},
		}
		d.Areas = &areas.Finder{DB: d.DB, URL: geoadmin.URL}
	})
	if _, err := s.db.Exec(context.Background(), `INSERT INTO places (kind, name, detail, source, source_id, geom) VALUES
		('pt_stop', 'Grindelwald, First', 'Seilbahn', 'didok', '8507396', ST_SetSRID(ST_MakePoint(8.0535, 46.6597), 4326)),
		('hut', 'Berghaus Bachalpsee', 'alpine_hut', 'osm', 'n1', ST_SetSRID(ST_MakePoint(8.0247, 46.6703), 4326))`); err != nil {
		t.Fatal(err)
	}
	return s
}

type bearerTransport struct{ token string }

func (b bearerTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+b.token)
	return http.DefaultTransport.RoundTrip(r)
}

func mcpSession(t *testing.T, s *testServer, token string) (*mcp.ClientSession, error) {
	t.Helper()
	client := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "1"}, nil)
	sess, err := client.Connect(context.Background(), &mcp.StreamableClientTransport{
		Endpoint: s.URL + "/api/v1/mcp", HTTPClient: &http.Client{Transport: bearerTransport{token}},
		DisableStandaloneSSE: true, MaxRetries: -1,
	}, nil)
	if err == nil {
		t.Cleanup(func() { _ = sess.Close() })
	}
	return sess, err
}

// call calls a tool and returns its text and its structured output in out.
func call(t *testing.T, sess *mcp.ClientSession, tool string, args map[string]any, out any) (string, bool) {
	t.Helper()
	res, err := sess.CallTool(context.Background(), &mcp.CallToolParams{Name: tool, Arguments: args})
	if err != nil {
		t.Fatalf("%s: %v", tool, err)
	}
	var text string
	for _, c := range res.Content {
		if tc, ok := c.(*mcp.TextContent); ok {
			text += tc.Text
		}
	}
	if !res.IsError && out != nil {
		b, _ := json.Marshal(res.StructuredContent)
		if err := json.Unmarshal(b, out); err != nil {
			t.Fatalf("%s: %v: %s", tool, err, b)
		}
	}
	return text, res.IsError
}

func TestMCP(t *testing.T) {
	s := newMCPServer(t)
	c, other := s.client(t), s.client(t)
	s.signup(c, "mira@example.ch", "mira")
	s.signup(other, "olaf@example.ch", "olaf")
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET speed_factor = 2 WHERE username = 'mira'`); err != nil {
		t.Fatal(err)
	}
	tok := newAccessToken(c, "Claude")

	// Only an access token opens it: not a session, not a wrong token.
	if _, err := mcpSession(t, s, "alvyo_pat_falsch"); err == nil {
		t.Error("wrong token connected")
	}
	if code, _ := c.do("POST", "/api/v1/mcp", map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
		"Accept", "application/json, text/event-stream"); code != http.StatusUnauthorized {
		t.Errorf("session: %d, want 401", code)
	}
	sess, err := mcpSession(t, s, tok.Token)
	if err != nil {
		t.Fatal(err)
	}

	tools, err := sess.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tl := range tools.Tools {
		names = append(names, tl.Name)
		if tl.Annotations == nil || !tl.Annotations.ReadOnlyHint {
			t.Errorf("%s is not marked read-only", tl.Name)
		}
	}
	if len(names) != 9 {
		t.Errorf("tools: %v", names)
	}

	var found searchPlacesResult
	if text, isErr := call(t, sess, "search_places", map[string]any{"query": "Bachalpsee"}, &found); isErr || len(found.Places) == 0 || found.Places[0].Kind != "hut" {
		t.Errorf("search_places: %s %+v", text, found)
	}

	// Planned at mira's pace (twice the signposts' time), with GPX.
	var plan planRouteResult
	text, isErr := call(t, sess, "plan_route", map[string]any{"from": "Grindelwald, First", "to": "Berghaus Bachalpsee", "gpx": true}, &plan)
	if isErr || len(plan.Places) != 2 || plan.Totals.DistanceKM < 2.8 || !strings.HasPrefix(plan.Totals.SAC, "T2") ||
		plan.Totals.YourTimeMin < 2*plan.Totals.HikingTimeMin-1 || !strings.HasPrefix(plan.GPX, "<?xml") {
		t.Errorf("plan_route: %s %+v", text, plan.Totals)
	}
	if !strings.Contains(text, "Grindelwald, First → Berghaus Bachalpsee") || !strings.Contains(text, "at your pace") {
		t.Errorf("plan_route text: %.300s", text)
	}
	// lat,lon or lon,lat.
	if text, isErr := call(t, sess, "plan_route", map[string]any{"from": "46.6597,8.0535", "to": "8.0247, 46.6703"}, &plan); isErr || plan.Places[1].Lon != 8.0247 {
		t.Errorf("plan_route with coordinates: %s", text)
	}
	if text, isErr := call(t, sess, "plan_route", map[string]any{"from": "Atlantis", "to": "Bachalpsee"}, nil); !isErr || !strings.Contains(text, `no place found for "Atlantis"`) {
		t.Errorf("unknown place: %v %s", isErr, text)
	}
	if text, isErr := call(t, sess, "plan_route", map[string]any{"from": "48.85,2.35", "to": "Bachalpsee"}, nil); !isErr || !strings.Contains(text, "outside Switzerland") {
		t.Errorf("Paris: %v %s", isErr, text)
	}
	// A place found by mistake far away is not planned to.
	if text, isErr := call(t, sess, "plan_route", map[string]any{"from": "Bachalpsee", "to": "46.0,9.5"}, nil); !isErr || !strings.Contains(text, "km apart") {
		t.Errorf("far apart: %v %s", isErr, text)
	}

	var reach reachResult
	if text, isErr := call(t, sess, "reach", map[string]any{"from": "Grindelwald, First"}, &reach); isErr || len(reach.Areas) != 3 || reach.Areas[2].Hours != 8 || reach.Areas[0].Outline != nil {
		t.Errorf("reach: %s %+v", text, reach)
	}

	// Saved routes and journeys: one's own, others' only when shared.
	_, raw := c.do("POST", "/api/v1/routes", newRouteBody("Gratweg", "private"))
	var mine savedRoute
	_ = json.Unmarshal(raw, &mine)
	_, raw = other.do("POST", "/api/v1/routes", newRouteBody("Olafs Weg", "private"))
	var olafs savedRoute
	_ = json.Unmarshal(raw, &olafs)
	_, raw = c.do("POST", "/api/v1/journeys", map[string]any{"title": "Zwei Tage"})
	jid := decodeJourney(t, raw).ID
	_, raw = c.do("POST", "/api/v1/journeys/"+jid+"/stages", map[string]any{})
	c.do("POST", "/api/v1/journeys/"+jid+"/stages/"+decodeJourney(t, raw).StageList[0].ID+"/route", stageRouteBody(8.0))

	var routesOut myRoutesResult
	if text, isErr := call(t, sess, "my_routes", nil, &routesOut); isErr || len(routesOut.Routes) != 1 || routesOut.Routes[0].ID != mine.ID || routesOut.Routes[0].Role != "owner" {
		t.Errorf("my_routes: %s", text)
	}
	var journeysOut myJourneysResult
	if text, isErr := call(t, sess, "my_journeys", nil, &journeysOut); isErr || len(journeysOut.Journeys) != 1 || journeysOut.Journeys[0].Stages != 1 {
		t.Errorf("my_journeys: %s", text)
	}
	var route getRouteResult
	if text, isErr := call(t, sess, "get_route", map[string]any{"id": mine.ID, "gpx": true}, &route); isErr || route.Title != "Gratweg" || !strings.Contains(route.GPX, "Gratweg") {
		t.Errorf("get_route: %s", text)
	}
	if text, isErr := call(t, sess, "get_route", map[string]any{"id": olafs.ID}, nil); !isErr || !strings.Contains(text, "not found") {
		t.Errorf("someone else's private route: %v %s", isErr, text)
	}
	var journey getJourneyResult
	if text, isErr := call(t, sess, "get_journey", map[string]any{"id": jid}, &journey); isErr || len(journey.Stages) != 1 || journey.Stages[0].Totals == nil {
		t.Errorf("get_journey: %s", text)
	}

	var cond conditionsResult
	if text, isErr := call(t, sess, "route_conditions", map[string]any{"route_id": mine.ID}, &cond); isErr || len(cond.Areas) != 3 || cond.Weather == nil {
		t.Errorf("route_conditions: %s", text)
	}
	if text, isErr := call(t, sess, "route_conditions", map[string]any{"from": "Grindelwald, First", "to": "Bachalpsee"}, &cond); isErr || len(cond.Areas) != 3 {
		t.Errorf("route_conditions of a planned route: %s", text)
	}
	if text, isErr := call(t, sess, "route_conditions", map[string]any{"route_id": olafs.ID}, nil); !isErr || !strings.Contains(text, "not found") {
		t.Errorf("conditions of someone else's private route: %v %s", isErr, text)
	}

	// Discovery: public routes only.
	if _, err := s.db.Exec(context.Background(), `UPDATE users SET email_verified_at = now() WHERE username = 'olaf'`); err != nil {
		t.Fatal(err)
	}
	if code, body := other.do("POST", "/api/v1/routes", newRouteBody("Olafs öffentlicher Weg", "public")); code != http.StatusCreated {
		t.Fatalf("public route: %d %s", code, body)
	}
	var disc discoverResult
	if text, isErr := call(t, sess, "discover", map[string]any{"near": "46.5,8.0", "radius_km": 5}, &disc); isErr || len(disc.Items) != 1 || disc.Items[0].Owner != "olaf" {
		t.Errorf("discover: %s", text)
	}

	// The access token was used: its owner sees when.
	_, raw = c.do("GET", "/api/v1/me/tokens", nil)
	if !strings.Contains(string(raw), "last_used_at") {
		t.Errorf("last used not noted: %s", raw)
	}
}
