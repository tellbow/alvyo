package httpapi

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
	mcpauth "github.com/modelcontextprotocol/go-sdk/auth"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/tellbow/alvyo/api/internal/auth"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/telemetry"
)

// mcpPath is the MCP endpoint (streamable HTTP) for AI assistants and the
// CLI. Only personal access tokens open it, and its tools only read.
const mcpPath = Prefix + "/mcp"

const mcpInstructions = `Alvyo plans hikes in Switzerland on the swisstopo map: Swiss hiking times (as on the yellow signposts), SAC grades (T1–T6), weather, trail closures and protected areas, public and official routes (Wanderland Schweiz), and the user's own routes and journeys (multi-day hikes in stages). Places are names (villages, stops, huts, summits) or "lat,lon". Times "at your pace" use the pace set in the user's account. Everything is read-only.`

// registerMCP serves the MCP endpoint: stateless, one answer per request.
func registerMCP(mux *http.ServeMux, d Deps) {
	server := mcp.NewServer(&mcp.Implementation{Name: "alvyo", Title: "Alvyo", Version: d.Version},
		&mcp.ServerOptions{Instructions: mcpInstructions})
	registerMCPTools(server, d)
	h := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return server },
		&mcp.StreamableHTTPOptions{Stateless: true, JSONResponse: true})
	// withSession has checked the token; the tools find the user in the
	// token info, since the SDK does not hand them the request's context.
	verify := func(ctx context.Context, _ string, _ *http.Request) (*mcpauth.TokenInfo, error) {
		u, ok := auth.UserFrom(ctx)
		if _, pat := auth.AccessTokenFrom(ctx); !ok || !pat {
			return nil, fmt.Errorf("%w: a personal access token is needed", mcpauth.ErrInvalidToken)
		}
		return &mcpauth.TokenInfo{UserID: u.ID.String(), Scopes: []string{"read"}, Extra: map[string]any{"user": u}}, nil
	}
	protected := mcpauth.RequireBearerToken(verify, &mcpauth.RequireBearerTokenOptions{AllowMissingExpiration: true})(h)
	mux.Handle(mcpPath, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		telemetry.Route(r.Context(), r.Method, mcpPath)
		protected.ServeHTTP(w, r)
	}))
}

// readOnly marks every tool: none changes anything, and they reach only
// Alvyo's own data and services.
var readOnly = &mcp.ToolAnnotations{ReadOnlyHint: true, IdempotentHint: true, OpenWorldHint: new(bool)}

// addTool registers a tool whose handler gets the caller (also in ctx, as
// for the HTTP handlers) and returns its output with a text for people
// and assistants.
func addTool[In, Out any](s *mcp.Server, name, title, desc string, h func(context.Context, dbq.User, In) (Out, string, error)) {
	t := &mcp.Tool{Name: name, Title: title, Description: desc, Annotations: readOnly}
	mcp.AddTool(s, t, func(ctx context.Context, req *mcp.CallToolRequest, in In) (*mcp.CallToolResult, Out, error) {
		var zero Out
		var u dbq.User
		if req.Extra != nil && req.Extra.TokenInfo != nil {
			u, _ = req.Extra.TokenInfo.Extra["user"].(dbq.User)
		}
		if u.ID == uuid.Nil {
			return nil, zero, errors.New("not logged in")
		}
		out, text, err := h(auth.WithUser(ctx, u), u, in)
		if err != nil {
			return nil, zero, toolError(ctx, name, err)
		}
		return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: text}}}, out, nil
	})
}

// toolError is what the assistant is told: the message of a client error,
// for others only that it failed (they are logged).
func toolError(ctx context.Context, tool string, err error) error {
	var se huma.StatusError
	if errors.As(err, &se) && (se.GetStatus() < 500 || se.GetStatus() == http.StatusServiceUnavailable) {
		return errors.New(se.Error())
	}
	slog.ErrorContext(ctx, "mcp tool", "tool", tool, "err", err)
	return errors.New("internal error, please retry later")
}

// resolvePlace finds a place by name, or takes "lat,lon" (or "lon,lat":
// within the covered area the two cannot be confused).
func resolvePlace(ctx context.Context, d Deps, u dbq.User, text string) (mcpPlace, error) {
	text = strings.TrimSpace(text)
	if a, b, ok := strings.Cut(text, ","); ok {
		x, errX := strconv.ParseFloat(strings.TrimSpace(a), 64)
		y, errY := strconv.ParseFloat(strings.TrimSpace(b), 64)
		if errX == nil && errY == nil {
			if inLon(y) && inLat(x) {
				x, y = y, x
			}
			if !inLon(x) || !inLat(y) {
				return mcpPlace{}, huma.Error422UnprocessableEntity(fmt.Sprintf("%q lies outside Switzerland and its surroundings", text))
			}
			return mcpPlace{Name: fmt.Sprintf("%.5f,%.5f", y, x), Lon: x, Lat: y}, nil
		}
	}
	if len([]rune(text)) < 2 || len([]rune(text)) > 80 {
		return mcpPlace{}, huma.Error422UnprocessableEntity("a place name needs 2 to 80 characters")
	}
	if !d.Limits.Search.Allow(u.ID.String()) {
		return mcpPlace{}, errTooMany
	}
	found, err := d.Places.Search(ctx, text, [2]float64{8.23, 46.8}, u.Locale)
	if err != nil {
		return mcpPlace{}, err
	}
	if len(found) == 0 {
		return mcpPlace{}, huma.Error404NotFound(fmt.Sprintf("no place found for %q", text))
	}
	f := found[0]
	return mcpPlace{Name: f.Name, Kind: f.Kind, Detail: f.Detail, Lon: f.At[0], Lat: f.At[1]}, nil
}

func inLon(v float64) bool { return v >= 5.7 && v <= 10.7 }
func inLat(v float64) bool { return v >= 45.65 && v <= 47.95 }

// mcpPlace is a place found by name or given as coordinates.
type mcpPlace struct {
	Name   string  `json:"name"`
	Kind   string  `json:"kind,omitempty" jsonschema:"pt_stop, hut, hotel, campsite, name (swisstopo's geographical names: villages, summits, passes …) or address"`
	Detail string  `json:"detail,omitempty" jsonschema:"Transport modes of a stop, the type of hut, or the kind of name and its municipality"`
	Lon    float64 `json:"lon"`
	Lat    float64 `json:"lat"`
}

// mcpTotals are a route's or journey's numbers.
type mcpTotals struct {
	DistanceKM    float64 `json:"distance_km"`
	AscentM       int     `json:"ascent_m"`
	DescentM      int     `json:"descent_m"`
	HikingTimeMin int     `json:"hiking_time_min" jsonschema:"Swiss hiking time as on the signposts, minutes, without breaks"`
	YourTimeMin   int     `json:"your_time_min" jsonschema:"The hiking time at the user's pace, minutes"`
	SAC           string  `json:"sac,omitempty" jsonschema:"SAC hiking scale of the hardest part (T1–T6), a range where unsure"`
}

func totalsOf(t routes.Totals, pace float32) mcpTotals {
	return mcpTotals{
		DistanceKM:    math.Round(t.DistanceM/100) / 10,
		AscentM:       int(math.Round(t.AscentM)),
		DescentM:      int(math.Round(t.DescentM)),
		HikingTimeMin: minutes(t.DurationS, 1),
		YourTimeMin:   minutes(t.DurationS, pace),
		SAC:           sacText(t.SACGrade, t.SACMax),
	}
}

func minutes(s int, pace float32) int {
	if pace <= 0 {
		pace = 1
	}
	return int(math.Round(float64(s) * float64(pace) / 60))
}

// String is the numbers in a line.
func (t mcpTotals) String() string {
	s := fmt.Sprintf("%.1f km, ↑%d m ↓%d m, %s", t.DistanceKM, t.AscentM, t.DescentM, hoursText(t.HikingTimeMin))
	if t.YourTimeMin != t.HikingTimeMin {
		s += fmt.Sprintf(" (%s at your pace)", hoursText(t.YourTimeMin))
	}
	if t.SAC != "" {
		s += ", " + t.SAC
	}
	return s
}

func sacText(grade, most int) string {
	switch {
	case grade <= 0:
		return ""
	case most > grade:
		return fmt.Sprintf("T%d–T%d", grade, most)
	}
	return fmt.Sprintf("T%d", grade)
}

func hoursText(minutes int) string {
	if minutes < 60 {
		return fmt.Sprintf("%d min", minutes)
	}
	return fmt.Sprintf("%d h %02d min", minutes/60, minutes%60)
}
