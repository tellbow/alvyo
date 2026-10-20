package httpapi

import (
	"bytes"
	"context"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/tellbow/alvyo/api/internal/areas"
	"github.com/tellbow/alvyo/api/internal/dbq"
	"github.com/tellbow/alvyo/api/internal/discover"
	"github.com/tellbow/alvyo/api/internal/done"
	"github.com/tellbow/alvyo/api/internal/gpx"
	"github.com/tellbow/alvyo/api/internal/grants"
	"github.com/tellbow/alvyo/api/internal/journeys"
	"github.com/tellbow/alvyo/api/internal/official"
	"github.com/tellbow/alvyo/api/internal/routes"
	"github.com/tellbow/alvyo/api/internal/routing"
	"github.com/tellbow/alvyo/api/internal/snow"
	"github.com/tellbow/alvyo/swiss/geo"
)

// maxVia bounds the places a planned route passes, as legs cost routing.
const maxVia = 8

// maxLegM: places farther apart (as the crow flies) are more likely a place
// found by mistake than a day's hike; a long route goes via places.
const maxLegM = 40_000

func registerMCPTools(s *mcp.Server, d Deps) {
	t := mcpTools{d}
	addTool(s, "search_places", "Search places",
		"Find places in Switzerland by name: villages, public transport stops, huts, hotels, campsites, summits, passes, lakes, addresses. The best match first.",
		t.searchPlaces)
	addTool(s, "plan_route", "Plan a route",
		"Plan a hike from a place to another, optionally via others, along hiking trails: distance, ascent and descent, the Swiss hiking time (as on the signposts and at the user's pace) and the SAC grade; the line as GPX on request. Nothing is saved.",
		t.planRoute)
	addTool(s, "reach", "How far one gets",
		"The areas reached on foot from a place within 2, 4 and 8 hours at the user's pace, timed by slope like the Swiss hiking time; optionally there and back within the hours.",
		t.reach)
	addTool(s, "route_conditions", "Conditions along a route",
		"MeteoSwiss's forecast at the start, highest point and end, closed trails and military shooting from today on, the protected areas crossed (wildlife rest areas, hunting reserves), and the snow on the way (satellite, with the part on terrain steeper than 30°), for a saved route (route_id) or one planned from places (from, via, to).",
		t.routeConditions)
	addTool(s, "discover", "Discover routes",
		"Public routes and journeys of Alvyo's users and the official routes of Wanderland Schweiz (SchweizMobil) around a place, the nearest first, at most 50.",
		t.discover)
	addTool(s, "my_routes", "My routes",
		"The user's own routes (planned, imported or recorded hikes), the most recently changed first, and the routes others shared with them.",
		t.myRoutes)
	addTool(s, "my_journeys", "My journeys",
		"The user's own journeys (multi-day hikes in stages) and those others shared with them.",
		t.myJourneys)
	addTool(s, "get_route", "Get a route",
		"A route the user may see (their own, shared with them, public, or unlisted with its token): its numbers, description and link; the line as GPX on request.",
		t.getRoute)
	addTool(s, "get_journey", "Get a journey",
		"A journey the user may see, with its stages: dates, numbers, start and end places, accommodation and transfers.",
		t.getJourney)
}

type mcpTools struct{ d Deps }

func (t mcpTools) url(kind, id, token string) string {
	u := t.d.PublicURL + "/" + kind + "/" + id
	if token != "" {
		u += "?t=" + token
	}
	return u
}

// search_places

type searchPlacesArgs struct {
	Query string `json:"query" jsonschema:"The name, or a part of it"`
}

type searchPlacesResult struct {
	Places []mcpPlace `json:"places"`
}

func (t mcpTools) searchPlaces(ctx context.Context, u dbq.User, in searchPlacesArgs) (searchPlacesResult, string, error) {
	q := strings.TrimSpace(in.Query)
	if len([]rune(q)) < 2 || len([]rune(q)) > 80 {
		return searchPlacesResult{}, "", huma.Error422UnprocessableEntity("query needs 2 to 80 characters")
	}
	if !t.d.Limits.Search.Allow(u.ID.String()) {
		return searchPlacesResult{}, "", errTooMany
	}
	found, err := t.d.Places.Search(ctx, q, [2]float64{8.23, 46.8}, u.Locale)
	if err != nil {
		return searchPlacesResult{}, "", err
	}
	out := searchPlacesResult{Places: []mcpPlace{}}
	var b strings.Builder
	for _, f := range found {
		p := mcpPlace{Name: f.Name, Kind: f.Kind, Detail: f.Detail, Lon: f.At[0], Lat: f.At[1]}
		out.Places = append(out.Places, p)
		fmt.Fprintf(&b, "%s (%s) %.5f,%.5f\n", p.Name, strings.TrimPrefix(p.Kind+", "+p.Detail, ", "), p.Lat, p.Lon)
	}
	if len(found) == 0 {
		b.WriteString("Nothing found.\n")
	}
	return out, b.String(), nil
}

// plan_route

type planArgs struct {
	From    string   `json:"from" jsonschema:"Start: a place name (e.g. Sargans, Weisstannen Oberdorf, Chamanna Jenatsch) or lat,lon"`
	Via     []string `json:"via,omitempty" jsonschema:"Places to pass on the way, in order (at most 8)"`
	To      string   `json:"to" jsonschema:"Destination, like from"`
	Profile string   `json:"profile,omitempty" jsonschema:"hike (default): hiking trails up to SAC T3; alpine: also alpine routes up to T6"`
}

type planRouteArgs struct {
	planArgs
	GPX bool `json:"gpx,omitempty" jsonschema:"Also return the line as a GPX 1.1 file"`
}

type planRouteResult struct {
	Places   []mcpPlace `json:"places" jsonschema:"Start, the places passed and the destination, as found"`
	Profile  string     `json:"profile"`
	Totals   mcpTotals  `json:"totals"`
	EleMinM  int        `json:"ele_min_m"`
	EleMaxM  int        `json:"ele_max_m"`
	Warnings []string   `json:"warnings" jsonschema:"e.g. a place far from the nearest path"`
	GPX      string     `json:"gpx,omitempty"`
}

// planned is a route planned from places, not saved.
type planned struct {
	places  []mcpPlace
	profile string
	legs    []routing.Leg
	totals  routes.Totals
}

func (p planned) line() [][3]float64 { return routes.Route{Legs: p.legs}.Line() }

func (t mcpTools) plan(ctx context.Context, u dbq.User, in planArgs) (planned, error) {
	switch in.Profile {
	case "":
		in.Profile = "hike"
	case "hike", "alpine":
	default:
		return planned{}, huma.Error422UnprocessableEntity("profile is hike or alpine")
	}
	if len(in.Via) > maxVia {
		return planned{}, huma.Error422UnprocessableEntity(fmt.Sprintf("at most %d places via", maxVia))
	}
	names := append(append([]string{in.From}, in.Via...), in.To)
	p := planned{profile: in.Profile}
	for _, n := range names {
		pl, err := resolvePlace(ctx, t.d, u, n)
		if err != nil {
			return planned{}, err
		}
		p.places = append(p.places, pl)
	}
	for i := 1; i < len(p.places); i++ {
		a, b := p.places[i-1], p.places[i]
		if dist := geo.Distance(geo.Point{Lon: a.Lon, Lat: a.Lat}, geo.Point{Lon: b.Lon, Lat: b.Lat}); dist > maxLegM {
			return planned{}, huma.Error422UnprocessableEntity(fmt.Sprintf(
				"%s (found for %q) and %s (found for %q) are %.0f km apart; at most %d km between places, add places via",
				a.Name, names[i-1], b.Name, names[i], dist/1000, maxLegM/1000))
		}
	}
	if !t.d.Limits.LegUser.AllowN(u.ID.String(), len(p.places)-1) {
		return planned{}, errTooMany
	}
	anchors := make([]routes.Anchor, len(p.places))
	for i, pl := range p.places {
		anchors[i] = routes.Anchor{Lon: pl.Lon, Lat: pl.Lat, Name: pl.Name}
		if i == 0 {
			continue
		}
		prev := p.places[i-1]
		leg, err := t.d.Router.Leg(ctx, routing.LegRequest{
			From: geo.Point{Lon: prev.Lon, Lat: prev.Lat}, To: geo.Point{Lon: pl.Lon, Lat: pl.Lat}, Profile: in.Profile,
		})
		if err := legError(ctx, err); err != nil {
			return planned{}, fmt.Errorf("%s → %s: %w", prev.Name, pl.Name, err)
		}
		p.legs = append(p.legs, leg)
	}
	legs, totals, err := routes.Check(routes.Content{Profile: in.Profile, Anchors: anchors, Legs: p.legs})
	if err != nil {
		return planned{}, routeError(err)
	}
	p.legs, p.totals = legs, totals
	return p, nil
}

func (t mcpTools) planRoute(ctx context.Context, u dbq.User, in planRouteArgs) (planRouteResult, string, error) {
	p, err := t.plan(ctx, u, in.planArgs)
	if err != nil {
		return planRouteResult{}, "", err
	}
	out := planRouteResult{
		Places: p.places, Profile: p.profile, Totals: totalsOf(p.totals, u.SpeedFactor),
		EleMinM: int(math.Round(p.totals.EleMinM)), EleMaxM: int(math.Round(p.totals.EleMaxM)),
		Warnings: []string{},
	}
	for i, l := range p.legs {
		for _, w := range l.Warnings {
			at := p.places[i].Name
			if strings.HasSuffix(w, "_to") {
				at = p.places[i+1].Name
			}
			if strings.HasPrefix(w, "snap_far") {
				w = at + " lies far from the nearest path; the route starts or ends where the path is nearest"
			}
			if !slices.Contains(out.Warnings, w) {
				out.Warnings = append(out.Warnings, w)
			}
		}
	}
	var b strings.Builder
	for i, pl := range p.places {
		if i > 0 {
			b.WriteString(" → ")
		}
		b.WriteString(pl.Name)
	}
	fmt.Fprintf(&b, " (%s): %s, %d–%d m above sea level\n", p.profile, out.Totals, out.EleMinM, out.EleMaxM)
	for _, w := range out.Warnings {
		fmt.Fprintf(&b, "Note: %s\n", w)
	}
	if in.GPX {
		title := p.places[0].Name + " – " + p.places[len(p.places)-1].Name
		if out.GPX, err = gpxText(gpx.Track{Name: title, Points: p.line(), Time: time.Now()}); err != nil {
			return planRouteResult{}, "", err
		}
		b.WriteString("\n" + out.GPX)
	}
	return out, b.String(), nil
}

func gpxText(tr gpx.Track) (string, error) {
	var buf bytes.Buffer
	err := gpx.Write(&buf, tr)
	return buf.String(), err
}

// reach

type reachArgs struct {
	From    string `json:"from" jsonschema:"Where one sets off: a place name or lat,lon"`
	Profile string `json:"profile,omitempty" jsonschema:"hike (default) or alpine"`
	Back    bool   `json:"back,omitempty" jsonschema:"Back at the start within the hours (there and back)"`
	Outline bool   `json:"outline,omitempty" jsonschema:"Also return each area's outline (polygon rings of [lon, lat])"`
}

type reachResult struct {
	From  mcpPlace       `json:"from"`
	Areas []mcpReachArea `json:"areas" jsonschema:"Within 2, 4 and 8 hours"`
}

type mcpReachArea struct {
	Hours   int            `json:"hours"`
	FarKM   float64        `json:"far_km" jsonschema:"The farthest point reached, as the crow flies"`
	BBox    [4]float64     `json:"bbox" jsonschema:"west, south, east, north"`
	Outline [][][2]float64 `json:"outline,omitempty"`
}

func (t mcpTools) reach(ctx context.Context, u dbq.User, in reachArgs) (reachResult, string, error) {
	if in.Profile == "" {
		in.Profile = "hike"
	}
	if in.Profile != "hike" && in.Profile != "alpine" {
		return reachResult{}, "", huma.Error422UnprocessableEntity("profile is hike or alpine")
	}
	from, err := resolvePlace(ctx, t.d, u, in.From)
	if err != nil {
		return reachResult{}, "", err
	}
	if !t.d.Limits.ReachUser.Allow(u.ID.String()) {
		return reachResult{}, "", errTooMany
	}
	select {
	case reachSlots <- struct{}{}:
		defer func() { <-reachSlots }()
	case <-ctx.Done():
		return reachResult{}, "", ctx.Err()
	}
	p := geo.Point{Lon: from.Lon, Lat: from.Lat}
	var found []routing.ReachArea
	if in.Back {
		found, err = t.d.Router.ReachBack(ctx, p, in.Profile, float64(u.SpeedFactor))
	} else {
		found, err = t.d.Router.GraphHopper.Reach(ctx, p, in.Profile, float64(u.SpeedFactor))
	}
	if err := legError(ctx, err); err != nil {
		return reachResult{}, "", err
	}
	out := reachResult{From: from, Areas: []mcpReachArea{}}
	var b strings.Builder
	way := "on foot"
	if in.Back {
		way = "there and back"
	}
	fmt.Fprintf(&b, "From %s, %s at your pace:\n", from.Name, way)
	for _, a := range found {
		ra := mcpReachArea{Hours: a.Hours, BBox: [4]float64{180, 90, -180, -90}}
		var far float64
		for _, ring := range a.Outline {
			for _, c := range ring {
				far = max(far, geo.Distance(p, geo.Point{Lon: c[0], Lat: c[1]}))
				ra.BBox = [4]float64{min(ra.BBox[0], c[0]), min(ra.BBox[1], c[1]), max(ra.BBox[2], c[0]), max(ra.BBox[3], c[1])}
			}
		}
		ra.FarKM = math.Round(far/100) / 10
		if in.Outline {
			ra.Outline = a.Outline
		}
		out.Areas = append(out.Areas, ra)
		fmt.Fprintf(&b, "within %d h: up to %.1f km away (west %.4f, south %.4f, east %.4f, north %.4f)\n",
			ra.Hours, ra.FarKM, ra.BBox[0], ra.BBox[1], ra.BBox[2], ra.BBox[3])
	}
	return out, b.String(), nil
}

// route_conditions

type conditionsArgs struct {
	RouteID string   `json:"route_id,omitempty" jsonschema:"A saved route's id; or from, via and to"`
	Token   string   `json:"token,omitempty" jsonschema:"Share token of an unlisted route (the t of its link)"`
	From    string   `json:"from,omitempty"`
	Via     []string `json:"via,omitempty"`
	To      string   `json:"to,omitempty"`
	Profile string   `json:"profile,omitempty" jsonschema:"hike (default) or alpine, when planned from places"`
	Date    string   `json:"date,omitempty" jsonschema:"The day of the hike (YYYY-MM-DD); beyond the forecast the climate normals of its month"`
}

type conditionsResult struct {
	Route   string            `json:"route"`
	Weather []mcpWeatherPlace `json:"weather"`
	Notices []mcpNotice       `json:"notices" jsonschema:"Closed trails and military shooting on the way, from today on"`
	Areas   []mcpArea         `json:"areas" jsonschema:"Protected areas crossed"`
	Snow    *mcpSnow          `json:"snow,omitempty" jsonschema:"Snow on the way, from the newest day of the snow cover; missing while there is none"`
}

type mcpSnow struct {
	Date      string           `json:"date" jsonschema:"The day of the snow cover"`
	SnowM     float64          `json:"snow_m" jsonschema:"In snow (from 50 %), 0 below 100 m"`
	SteepM    *float64         `json:"steep_m,omitempty" jsonschema:"Of that, on terrain steeper than 30°; missing where the slope is not known (abroad)"`
	PatchesM  float64          `json:"patches_m" jsonschema:"Elsewhere in patches (15–50 %), 0 below 100 m"`
	Stretches []mcpSnowStretch `json:"stretches"`
	Note      string           `json:"note"`
}

type mcpSnowStretch struct {
	FromM  float64 `json:"from_m" jsonschema:"From the start"`
	ToM    float64 `json:"to_m"`
	SteepM float64 `json:"steep_m"`
}

// snowNote is what the snow cover cannot say, and its credit.
const snowNote = "Satellite, 60 m; under clouds up to 7 days old: a short snow field can be missing, depth and hardness are not known. The BFU advises planning hikes so as not to meet snow fields and turning back in doubt. " + snow.Attribution + "."

type mcpWeatherPlace struct {
	At       []string        `json:"at" jsonschema:"start, top (the highest point), end"`
	Point    string          `json:"point" jsonschema:"MeteoSwiss's forecast point"`
	HeightM  int             `json:"height_m"`
	Days     []mcpWeatherDay `json:"days"`
	Climate  *mcpClimate     `json:"climate,omitempty" jsonschema:"What is usual in the month of the date, beyond the forecast"`
	Forecast time.Time       `json:"forecast" jsonschema:"When MeteoSwiss made the forecast"`
}

type mcpWeatherDay struct {
	Date   string  `json:"date"`
	MinC   float64 `json:"min_c"`
	MaxC   float64 `json:"max_c"`
	RainMM float64 `json:"rain_mm"`
}

type mcpClimate struct {
	Month    int     `json:"month"`
	MinC     float64 `json:"min_c"`
	MaxC     float64 `json:"max_c"`
	RainMM   float64 `json:"rain_mm" jsonschema:"In the whole month"`
	RainDays float64 `json:"rain_days" jsonschema:"Days of the month with at least 1 mm"`
}

type mcpNotice struct {
	Kind   string   `json:"kind" jsonschema:"closure or shooting"`
	Title  string   `json:"title"`
	Reason string   `json:"reason,omitempty"`
	From   string   `json:"from,omitempty"`
	To     string   `json:"to,omitempty"`
	Days   []string `json:"days,omitempty" jsonschema:"Shooting days, with the hours (0800–1700) when known"`
}

type mcpArea struct {
	Kind    string `json:"kind" jsonschema:"wildlife_rest or hunting_reserve"`
	Name    string `json:"name"`
	Binding bool   `json:"binding" jsonschema:"Legally binding; otherwise a recommendation"`
	Rule    string `json:"rule"`
	Period  string `json:"period,omitempty" jsonschema:"When the rule applies (MM-DD to MM-DD, both included), if not all year"`
	Link    string `json:"link,omitempty"`
}

func (t mcpTools) routeConditions(ctx context.Context, u dbq.User, in conditionsArgs) (conditionsResult, string, error) {
	if in.Date != "" {
		if _, err := time.Parse(time.DateOnly, in.Date); err != nil {
			return conditionsResult{}, "", huma.Error422UnprocessableEntity("date is YYYY-MM-DD")
		}
	}
	var out conditionsResult
	var line [][3]float64
	if in.RouteID != "" {
		r, _, err := loadRoute(ctx, t.d, in.RouteID, in.Token)
		if err != nil {
			return out, "", err
		}
		out.Route, line = r.Title, r.Line()
	} else {
		if in.From == "" || in.To == "" {
			return out, "", huma.Error422UnprocessableEntity("route_id, or from and to, are needed")
		}
		p, err := t.plan(ctx, u, planArgs{From: in.From, Via: in.Via, To: in.To, Profile: in.Profile})
		if err != nil {
			return out, "", err
		}
		out.Route, line = p.places[0].Name+" – "+p.places[len(p.places)-1].Name, p.line()
	}
	if len(line) < 2 {
		return out, "", huma.Error422UnprocessableEntity("the route has no line")
	}
	if !t.d.Limits.LegUser.Allow(u.ID.String()) {
		return out, "", errTooMany
	}
	pts := make([]geo.Point, len(line))
	for i, c := range line {
		pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	found, notices, err := crossedAreas(ctx, t.d, pts)
	if err != nil {
		return out, "", err
	}
	if geo.CumulativeDistance(pts)[len(pts)-1] <= snow.MaxLineM {
		sa, err := t.d.Snow.Along(ctx, pts)
		if err != nil {
			return out, "", err
		}
		if sa.Date != "" {
			ms := &mcpSnow{Date: sa.Date, SnowM: sa.SnowM, PatchesM: sa.PatchesM, Stretches: []mcpSnowStretch{}, Note: snowNote}
			if sa.Slopes {
				ms.SteepM = &sa.SteepM
			}
			for _, st := range sa.Stretches {
				ms.Stretches = append(ms.Stretches, mcpSnowStretch{FromM: st.FromM, ToM: st.ToM, SteepM: st.SteepM})
			}
			out.Snow = ms
		}
	}
	lang := u.Locale
	out.Weather, out.Notices, out.Areas = []mcpWeatherPlace{}, []mcpNotice{}, []mcpArea{}
	if t.d.Weather != nil && !t.d.Weather.Run().IsZero() {
		for _, wp := range lineWeather(t.d, line, in.Date) {
			w := mcpWeatherPlace{At: wp.Roles, Point: wp.Point.Name, HeightM: int(wp.Point.Height), Days: []mcpWeatherDay{}, Forecast: t.d.Weather.Run()}
			for _, day := range wp.Days {
				if in.Date == "" || day.Date == in.Date {
					w.Days = append(w.Days, mcpWeatherDay{Date: day.Date, MinC: day.MinC, MaxC: day.MaxC, RainMM: day.RainMM})
				}
			}
			if c := wp.Climate; c != nil {
				w.Climate = &mcpClimate{Month: c.Month, MinC: c.MinC, MaxC: c.MaxC, RainMM: c.RainMM, RainDays: c.RainDays}
			}
			out.Weather = append(out.Weather, w)
		}
	}
	for _, n := range notices {
		mn := mcpNotice{Kind: n.Kind, Title: textIn(n.Title, lang), From: n.From, To: n.To}
		if n.Reason != nil {
			mn.Reason = textIn(*n.Reason, lang)
		}
		for _, sd := range n.Days {
			if sd.From != "" {
				sd.Date += " " + sd.From + "–" + sd.To // hours as «0800»
			}
			mn.Days = append(mn.Days, sd.Date)
		}
		out.Notices = append(out.Notices, mn)
	}
	for _, a := range found {
		ma := mcpArea{Kind: a.Kind, Name: a.Name, Binding: a.Binding, Rule: textIn(a.Rule, lang), Link: a.Link}
		if a.Period != nil {
			ma.Period = a.Period.From + " to " + a.Period.To
		}
		out.Areas = append(out.Areas, ma)
	}
	return out, out.text(), nil
}

// textIn is a text in the user's language, else in German.
func textIn(t areas.Texts, lang string) string {
	s := map[string]string{"de": t.De, "fr": t.Fr, "it": t.It, "en": t.En}[lang]
	if s == "" {
		return t.De
	}
	return s
}

func (c conditionsResult) text() string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s\n\nWeather:\n", c.Route)
	if len(c.Weather) == 0 {
		b.WriteString("no forecast\n")
	}
	for _, w := range c.Weather {
		fmt.Fprintf(&b, "%s (%s, %d m):", strings.Join(w.At, ", "), w.Point, w.HeightM)
		for _, d := range w.Days {
			fmt.Fprintf(&b, " %s %.0f…%.0f °C %.1f mm;", d.Date, d.MinC, d.MaxC, d.RainMM)
		}
		if w.Climate != nil {
			fmt.Fprintf(&b, " usual in month %d: %.0f…%.0f °C, %.0f days with rain;", w.Climate.Month, w.Climate.MinC, w.Climate.MaxC, w.Climate.RainDays)
		}
		b.WriteString("\n")
	}
	b.WriteString("\nClosures and shooting:\n")
	if len(c.Notices) == 0 {
		b.WriteString("none\n")
	}
	for _, n := range c.Notices {
		fmt.Fprintf(&b, "%s: %s", n.Kind, n.Title)
		if n.Reason != "" {
			fmt.Fprintf(&b, " (%s)", n.Reason)
		}
		if n.From != "" || n.To != "" {
			fmt.Fprintf(&b, ", %s to %s", n.From, n.To)
		}
		if len(n.Days) > 0 {
			fmt.Fprintf(&b, ", %s", strings.Join(n.Days, ", "))
		}
		b.WriteString("\n")
	}
	b.WriteString("\nProtected areas:\n")
	if len(c.Areas) == 0 {
		b.WriteString("none\n")
	}
	for _, a := range c.Areas {
		kind := "recommended"
		if a.Binding {
			kind = "binding"
		}
		fmt.Fprintf(&b, "%s (%s, %s): %s", a.Name, strings.ReplaceAll(a.Kind, "_", " "), kind, a.Rule)
		if a.Period != "" {
			fmt.Fprintf(&b, ", %s", a.Period)
		}
		b.WriteString("\n")
	}
	if sn := c.Snow; sn != nil {
		fmt.Fprintf(&b, "\nSnow (%s):\n", sn.Date)
		if sn.SnowM == 0 {
			b.WriteString("none")
		} else {
			fmt.Fprintf(&b, "%.0f m in snow", sn.SnowM)
			if sn.SteepM != nil {
				fmt.Fprintf(&b, ", %.0f m of it steeper than 30°", *sn.SteepM)
			}
		}
		if sn.PatchesM > 0 {
			fmt.Fprintf(&b, "; patches on %.0f m", sn.PatchesM)
		}
		b.WriteString("\n")
		for _, st := range sn.Stretches {
			fmt.Fprintf(&b, "%.1f–%.1f km", st.FromM/1000, st.ToM/1000)
			if sn.SteepM != nil && st.SteepM > 0 {
				fmt.Fprintf(&b, " (%.0f m steep)", st.SteepM)
			}
			b.WriteString("\n")
		}
		b.WriteString(sn.Note + "\n")
	}
	return b.String()
}

// discover

type discoverArgs struct {
	Near     string  `json:"near" jsonschema:"A place name or lat,lon"`
	RadiusKM float64 `json:"radius_km,omitempty" jsonschema:"Around it, 1 to 50 km (default 10)"`
	Kind     string  `json:"kind,omitempty" jsonschema:"route or journey; both if empty"`
	Official string  `json:"official,omitempty" jsonschema:"only: the official routes of Wanderland Schweiz; none: those of Alvyo's users; both if empty"`
	SACMax   int     `json:"sac_max,omitempty" jsonschema:"Hardest SAC grade allowed, 1 to 6"`
	MinHours float64 `json:"min_hours,omitempty" jsonschema:"Hiking time at least (journeys: the longest stage)"`
	MaxHours float64 `json:"max_hours,omitempty" jsonschema:"Hiking time at most (journeys: the longest stage)"`
}

type discoverResult struct {
	Near  mcpPlace          `json:"near"`
	Items []mcpDiscoverItem `json:"items"`
	More  bool              `json:"more" jsonschema:"There are more: narrow the radius or the filters"`
}

type mcpDiscoverItem struct {
	Kind          string    `json:"kind" jsonschema:"route or journey"`
	ID            string    `json:"id"`
	Title         string    `json:"title"`
	Owner         string    `json:"owner"`
	Official      string    `json:"official,omitempty" jsonschema:"The official route's kind and number at SchweizMobil, e.g. regional 34"`
	Stages        int       `json:"stages,omitempty"`
	Totals        mcpTotals `json:"totals" jsonschema:"Journeys: all stages together"`
	LongestTimeMn int       `json:"longest_stage_min,omitempty" jsonschema:"Journeys: the longest stage's hiking time, minutes"`
	URL           string    `json:"url"`
}

func (t mcpTools) discover(ctx context.Context, u dbq.User, in discoverArgs) (discoverResult, string, error) {
	if in.RadiusKM == 0 {
		in.RadiusKM = 10
	}
	switch {
	case in.RadiusKM < 1 || in.RadiusKM > 50:
		return discoverResult{}, "", huma.Error422UnprocessableEntity("radius_km is 1 to 50")
	case in.Kind != "" && in.Kind != "route" && in.Kind != "journey":
		return discoverResult{}, "", huma.Error422UnprocessableEntity("kind is route or journey")
	case in.Official != "" && in.Official != "only" && in.Official != "none":
		return discoverResult{}, "", huma.Error422UnprocessableEntity("official is only or none")
	case in.SACMax < 0 || in.SACMax > 6 || in.MinHours < 0 || in.MaxHours < 0:
		return discoverResult{}, "", huma.Error422UnprocessableEntity("sac_max is 1 to 6, hours not negative")
	}
	near, err := resolvePlace(ctx, t.d, u, in.Near)
	if err != nil {
		return discoverResult{}, "", err
	}
	dLat := in.RadiusKM / 111.32
	dLon := dLat / math.Cos(near.Lat*math.Pi/180)
	items, more, err := t.d.Discover.Search(ctx, discover.Query{
		West: near.Lon - dLon, South: near.Lat - dLat, East: near.Lon + dLon, North: near.Lat + dLat,
		Kind: in.Kind, SACMax: in.SACMax, Official: in.Official,
		MinDurationS: int(in.MinHours * 3600), MaxDurationS: int(in.MaxHours * 3600),
	})
	if err != nil {
		return discoverResult{}, "", err
	}
	out := discoverResult{Near: near, Items: []mcpDiscoverItem{}, More: more}
	var b strings.Builder
	fmt.Fprintf(&b, "Within %.0f km of %s:\n", in.RadiusKM, near.Name)
	for _, it := range items {
		mi := mcpDiscoverItem{
			Kind: it.Kind, ID: it.ID, Title: it.Title, Owner: it.OwnerUsername, Stages: it.Stages,
			Totals: totalsOf(routes.Totals{DistanceM: it.DistanceM, AscentM: it.AscentM, DurationS: it.DurationS,
				SACGrade: it.SACGrade, SACMax: it.SACMax}, u.SpeedFactor),
			URL: t.url(it.Kind+"s", it.ID, ""),
		}
		if it.Official != nil {
			mi.Official = it.Official.Kind + " " + it.Official.Number
		}
		if it.Kind == "journey" {
			mi.LongestTimeMn = minutes(it.LongestS, 1)
		}
		// Discovery knows ascent only.
		mi.Totals.DescentM = 0
		out.Items = append(out.Items, mi)
		fmt.Fprintf(&b, "- %s", mi.Title)
		if mi.Official != "" {
			fmt.Fprintf(&b, " (official %s route)", mi.Official)
		} else {
			fmt.Fprintf(&b, " (by %s)", mi.Owner)
		}
		if mi.Stages > 0 {
			fmt.Fprintf(&b, ", journey of %d stages, the longest %s", mi.Stages, hoursText(mi.LongestTimeMn))
		}
		fmt.Fprintf(&b, ": %.1f km, ↑%d m, %s", mi.Totals.DistanceKM, mi.Totals.AscentM, hoursText(mi.Totals.HikingTimeMin))
		if mi.Totals.SAC != "" {
			b.WriteString(", " + mi.Totals.SAC)
		}
		fmt.Fprintf(&b, ". %s id %s, %s\n", mi.Kind, mi.ID, mi.URL)
	}
	if len(items) == 0 {
		b.WriteString("Nothing found.\n")
	}
	if more {
		b.WriteString("There are more: narrow the radius or the filters.\n")
	}
	return out, b.String(), nil
}

// my_routes, my_journeys

type noArgs struct{}

type mcpRouteItem struct {
	ID         string    `json:"id"`
	Title      string    `json:"title"`
	Owner      string    `json:"owner"`
	Visibility string    `json:"visibility" jsonschema:"private, unlisted (by link) or public"`
	Role       string    `json:"role" jsonschema:"owner, editor or viewer"`
	Recorded   bool      `json:"recorded,omitempty" jsonschema:"Recorded with the app while hiking"`
	HikedOn    string    `json:"hiked_on,omitempty" jsonschema:"When the user hiked it"`
	Tags       []string  `json:"tags"`
	Totals     mcpTotals `json:"totals"`
	UpdatedAt  time.Time `json:"updated_at"`
	URL        string    `json:"url"`
}

type myRoutesResult struct {
	Routes []mcpRouteItem `json:"routes"`
}

func (t mcpTools) routeItem(s routes.Summary, role string, pace float32) mcpRouteItem {
	it := mcpRouteItem{
		ID: s.ID, Title: s.Title, Owner: s.OwnerUsername, Visibility: s.Visibility, Role: role,
		Recorded: s.Hike != nil, Tags: s.Tags, Totals: totalsOf(s.Totals, pace), UpdatedAt: s.UpdatedAt,
		URL: t.url("routes", s.ID, ""),
	}
	if it.Tags == nil {
		it.Tags = []string{}
	}
	if s.DoneOn != nil {
		it.HikedOn = *s.DoneOn
	}
	return it
}

func (it mcpRouteItem) line() string {
	s := fmt.Sprintf("- %s: %s", it.Title, it.Totals)
	if it.Role != "owner" {
		s += fmt.Sprintf(", by %s (%s)", it.Owner, it.Role)
	}
	if it.Recorded {
		s += ", recorded"
	}
	if it.HikedOn != "" {
		s += ", hiked " + it.HikedOn
	}
	return s + fmt.Sprintf(". id %s, %s\n", it.ID, it.Visibility)
}

func (t mcpTools) myRoutes(ctx context.Context, u dbq.User, _ noArgs) (myRoutesResult, string, error) {
	own, err := t.d.Routes.ListByOwner(ctx, u.ID, 500)
	if err != nil {
		return myRoutesResult{}, "", err
	}
	uid, email := grants.Grantee(u)
	shared, err := t.d.Routes.ListSharedWith(ctx, uid, email, 500)
	if err != nil {
		return myRoutesResult{}, "", err
	}
	all := make([]routes.Summary, 0, len(own)+len(shared))
	roles := make([]string, 0, cap(all))
	for _, s := range own {
		all, roles = append(all, s), append(roles, "owner")
	}
	for _, s := range shared {
		all, roles = append(all, s.Summary), append(roles, s.Role)
	}
	if err := doneDays(ctx, t.d, u.ID, done.Route, len(all),
		func(i int) string { return all[i].ID }, func(i int, day *string) { all[i].DoneOn = day }); err != nil {
		return myRoutesResult{}, "", err
	}
	out := myRoutesResult{Routes: []mcpRouteItem{}}
	var b strings.Builder
	for i, s := range all {
		it := t.routeItem(s, roles[i], u.SpeedFactor)
		out.Routes = append(out.Routes, it)
		b.WriteString(it.line())
	}
	if len(all) == 0 {
		b.WriteString("No routes yet.\n")
	}
	return out, b.String(), nil
}

type mcpJourneyItem struct {
	ID         string   `json:"id"`
	Title      string   `json:"title"`
	Owner      string   `json:"owner"`
	Visibility string   `json:"visibility"`
	Role       string   `json:"role" jsonschema:"owner, editor or viewer"`
	Stages     int      `json:"stages"`
	StagesDone int      `json:"stages_done"`
	HikedOn    string   `json:"hiked_on,omitempty"`
	Tags       []string `json:"tags"`
	DistanceKM float64  `json:"distance_km"`
	AscentM    int      `json:"ascent_m"`
	// Summaries have no SAC grade and descent; get_journey has them.
	HikingTimeMin int       `json:"hiking_time_min" jsonschema:"All stages together, as on the signposts"`
	UpdatedAt     time.Time `json:"updated_at"`
	URL           string    `json:"url"`
}

type myJourneysResult struct {
	Journeys []mcpJourneyItem `json:"journeys"`
}

func (t mcpTools) myJourneys(ctx context.Context, u dbq.User, _ noArgs) (myJourneysResult, string, error) {
	own, err := t.d.Journeys.ListByOwner(ctx, u.ID)
	if err != nil {
		return myJourneysResult{}, "", err
	}
	uid, email := grants.Grantee(u)
	shared, err := t.d.Journeys.ListSharedWith(ctx, uid, email)
	if err != nil {
		return myJourneysResult{}, "", err
	}
	all := make([]journeys.Summary, 0, len(own)+len(shared))
	roles := make([]string, 0, cap(all))
	for _, s := range own {
		all, roles = append(all, s), append(roles, "owner")
	}
	for _, s := range shared {
		all, roles = append(all, s.Summary), append(roles, s.Role)
	}
	if err := doneDays(ctx, t.d, u.ID, done.Journey, len(all),
		func(i int) string { return all[i].ID }, func(i int, day *string) { all[i].DoneOn = day }); err != nil {
		return myJourneysResult{}, "", err
	}
	out := myJourneysResult{Journeys: []mcpJourneyItem{}}
	var b strings.Builder
	for i, s := range all {
		it := mcpJourneyItem{
			ID: s.ID, Title: s.Title, Owner: s.OwnerUsername, Visibility: s.Visibility, Role: roles[i],
			Stages: s.Stages, StagesDone: s.StagesDone, Tags: s.Tags,
			DistanceKM: math.Round(s.DistanceM/100) / 10, AscentM: int(math.Round(s.AscentM)),
			HikingTimeMin: minutes(s.DurationS, 1), UpdatedAt: s.UpdatedAt, URL: t.url("journeys", s.ID, ""),
		}
		if it.Tags == nil {
			it.Tags = []string{}
		}
		if s.DoneOn != nil {
			it.HikedOn = *s.DoneOn
		}
		out.Journeys = append(out.Journeys, it)
		fmt.Fprintf(&b, "- %s: %d stages (%d done), %.1f km, ↑%d m, %s", it.Title, it.Stages, it.StagesDone,
			it.DistanceKM, it.AscentM, hoursText(it.HikingTimeMin))
		if it.Role != "owner" {
			fmt.Fprintf(&b, ", by %s (%s)", it.Owner, it.Role)
		}
		fmt.Fprintf(&b, ". id %s, %s\n", it.ID, it.Visibility)
	}
	if len(all) == 0 {
		b.WriteString("No journeys yet.\n")
	}
	return out, b.String(), nil
}

// get_route, get_journey

type getRouteArgs struct {
	ID    string `json:"id" jsonschema:"The route's id (from its link /routes/{id})"`
	Token string `json:"token,omitempty" jsonschema:"Share token of an unlisted route (the t of its link)"`
	GPX   bool   `json:"gpx,omitempty" jsonschema:"Also return the line as a GPX 1.1 file"`
}

type getRouteResult struct {
	mcpRouteItem
	Description string   `json:"description"`
	Profile     string   `json:"profile" jsonschema:"hike or alpine"`
	Places      []string `json:"places" jsonschema:"The named points it was planned through"`
	EleMinM     int      `json:"ele_min_m"`
	EleMaxM     int      `json:"ele_max_m"`
	JourneyID   string   `json:"journey_id,omitempty" jsonschema:"Set for a journey's stage"`
	Official    string   `json:"official,omitempty"`
	GPX         string   `json:"gpx,omitempty"`
}

func (t mcpTools) getRoute(ctx context.Context, u dbq.User, in getRouteArgs) (getRouteResult, string, error) {
	r, role, err := loadRoute(ctx, t.d, in.ID, in.Token)
	if err != nil {
		return getRouteResult{}, "", err
	}
	st, err := t.d.Done.Of(ctx, u.ID, done.Route, uuid.MustParse(r.ID))
	if err != nil {
		return getRouteResult{}, "", err
	}
	r.DoneOn = day(st.On)
	info, err := official.ForRoute(ctx, t.d.DB, uuid.MustParse(r.ID))
	if err != nil {
		return getRouteResult{}, "", err
	}
	out := getRouteResult{
		mcpRouteItem: t.routeItem(r.Summary, role.String(), u.SpeedFactor),
		Description:  r.Description, Profile: r.Profile, Places: []string{}, JourneyID: r.JourneyID,
		EleMinM: int(math.Round(r.Totals.EleMinM)), EleMaxM: int(math.Round(r.Totals.EleMaxM)),
	}
	out.URL = t.url("routes", r.ID, in.Token)
	for _, a := range r.Anchors {
		if a.Name != "" {
			out.Places = append(out.Places, a.Name)
		}
	}
	if info != nil {
		out.Official = info.Kind + " " + info.Number
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s (%s)\n%s, %d–%d m above sea level\n", out.Title, out.URL, out.Totals, out.EleMinM, out.EleMaxM)
	if len(out.Places) > 0 {
		fmt.Fprintf(&b, "Via: %s\n", strings.Join(out.Places, " → "))
	}
	if out.Official != "" {
		fmt.Fprintf(&b, "Official %s route of Wanderland Schweiz\n", out.Official)
	} else {
		fmt.Fprintf(&b, "By %s, %s, your role: %s\n", out.Owner, out.Visibility, out.Role)
	}
	if out.HikedOn != "" {
		fmt.Fprintf(&b, "Hiked on %s\n", out.HikedOn)
	}
	if out.Description != "" {
		fmt.Fprintf(&b, "\n%s\n", out.Description)
	}
	if in.GPX {
		if out.GPX, err = gpxText(gpx.Track{Name: r.Title, Description: r.Description, Author: r.OwnerUsername,
			Link: t.url("routes", r.ID, ""), Points: r.Line(), Time: r.UpdatedAt}); err != nil {
			return getRouteResult{}, "", err
		}
		b.WriteString("\n" + out.GPX)
	}
	return out, b.String(), nil
}

type getJourneyArgs struct {
	ID    string `json:"id" jsonschema:"The journey's id (from its link /journeys/{id})"`
	Token string `json:"token,omitempty" jsonschema:"Share token of an unlisted journey (the t of its link)"`
}

type getJourneyResult struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Owner       string     `json:"owner"`
	Visibility  string     `json:"visibility"`
	Role        string     `json:"role"`
	Official    string     `json:"official,omitempty"`
	HikedOn     string     `json:"hiked_on,omitempty"`
	Totals      mcpTotals  `json:"totals"`
	Stages      []mcpStage `json:"stages"`
	URL         string     `json:"url"`
}

type mcpStage struct {
	Number         int        `json:"number"`
	Title          string     `json:"title"`
	Date           string     `json:"date,omitempty"`
	Status         string     `json:"status" jsonschema:"planned, done or skipped"`
	TransferBefore string     `json:"transfer_before,omitempty" jsonschema:"How one gets to its start: pt (public transport), cablecar or other"`
	Start          string     `json:"start,omitempty"`
	End            string     `json:"end,omitempty"`
	Accommodation  string     `json:"accommodation,omitempty" jsonschema:"Where the hiker sleeps after it"`
	RouteID        string     `json:"route_id,omitempty"`
	Totals         *mcpTotals `json:"totals,omitempty" jsonschema:"Missing while the stage has no route"`
}

func (t mcpTools) getJourney(ctx context.Context, u dbq.User, in getJourneyArgs) (getJourneyResult, string, error) {
	j, role, err := loadJourney(ctx, t.d, in.ID, in.Token)
	if err != nil {
		return getJourneyResult{}, "", err
	}
	st, err := t.d.Done.Of(ctx, u.ID, done.Journey, uuid.MustParse(j.ID))
	if err != nil {
		return getJourneyResult{}, "", err
	}
	info, err := official.ForJourney(ctx, t.d.DB, uuid.MustParse(j.ID))
	if err != nil {
		return getJourneyResult{}, "", err
	}
	out := getJourneyResult{
		ID: j.ID, Title: j.Title, Description: j.Description, Owner: j.OwnerUsername, Visibility: j.Visibility,
		Role: role.String(), Totals: totalsOf(j.Totals, u.SpeedFactor), Stages: []mcpStage{},
		URL: t.url("journeys", j.ID, in.Token),
	}
	if d := day(st.On); d != nil {
		out.HikedOn = *d
	}
	if info != nil {
		out.Official = info.Kind + " " + info.Number
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s (%s)\n%d stages, %s\n", out.Title, out.URL, len(j.StageList), out.Totals)
	if out.Official != "" {
		fmt.Fprintf(&b, "Official %s route of Wanderland Schweiz\n", out.Official)
	} else {
		fmt.Fprintf(&b, "By %s, %s, your role: %s\n", out.Owner, out.Visibility, out.Role)
	}
	if out.Description != "" {
		fmt.Fprintf(&b, "\n%s\n", out.Description)
	}
	b.WriteString("\n")
	for i, s := range j.StageList {
		ms := mcpStage{Number: i + 1, Title: s.Title, Status: s.Status, Accommodation: s.Accommodation}
		if s.PlannedDate != nil {
			ms.Date = *s.PlannedDate
		}
		if s.TransferBefore != nil {
			ms.TransferBefore = *s.TransferBefore
		}
		if s.StartPlace != nil {
			ms.Start = s.StartPlace.Name
		}
		if s.EndPlace != nil {
			ms.End = s.EndPlace.Name
		}
		if s.Route != nil {
			ms.RouteID = s.Route.ID
			tt := totalsOf(s.Route.Totals, u.SpeedFactor)
			ms.Totals = &tt
		}
		out.Stages = append(out.Stages, ms)
		fmt.Fprintf(&b, "%d. %s", ms.Number, ms.Title)
		if ms.Date != "" {
			fmt.Fprintf(&b, " (%s)", ms.Date)
		}
		if ms.Status != "planned" {
			fmt.Fprintf(&b, " [%s]", ms.Status)
		}
		if ms.Totals != nil {
			fmt.Fprintf(&b, ": %s", ms.Totals)
		}
		if ms.Start != "" || ms.End != "" {
			fmt.Fprintf(&b, "; %s → %s", ms.Start, ms.End)
		}
		if ms.TransferBefore != "" {
			fmt.Fprintf(&b, "; transfer before: %s", ms.TransferBefore)
		}
		if ms.Accommodation != "" {
			fmt.Fprintf(&b, "; night: %s", ms.Accommodation)
		}
		if ms.RouteID != "" {
			fmt.Fprintf(&b, "; route id %s", ms.RouteID)
		}
		b.WriteString("\n")
	}
	return out, b.String(), nil
}
