package imports

import (
	"context"
	"errors"
	"math"
	"strings"

	"github.com/google/uuid"

	"github.com/tellbow/odysgeh/api/internal/journeys"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/api/internal/routing"
	"github.com/tellbow/odysgeh/swiss/geo"
)

const (
	// simplifyM removes GPS jitter (metres) before densifying.
	simplifyM = 5
	// legM is the target leg length: anchors this far apart keep the
	// imported line when a nearby part is edited and re-routed.
	legM = 2000
	// minTrackM rejects tracks that are hardly more than a point.
	minTrackM = 50
)

// Covered area (Switzerland and Liechtenstein with a margin), as in the API.
const minLon, maxLon, minLat, maxLat = 5.9, 10.6, 45.8, 47.9

// Reasons a track is not imported.
var (
	ErrOutside = errors.New("the track leaves Switzerland and Liechtenstein")
	ErrShort   = errors.New("the track is too short")
)

// Importer creates routes and journeys from tracks.
type Importer struct {
	Router   *routing.Router
	Routes   *routes.Store
	Journeys *journeys.Store
}

// Content turns a track into planner content: simplified, with elevation and
// trail data, and split into legs of about 2 km.
func (im *Importer) Content(ctx context.Context, t Track) (routes.Content, error) {
	for _, p := range t.Points {
		if p.Lon < minLon || p.Lon > maxLon || p.Lat < minLat || p.Lat > maxLat {
			return routes.Content{}, ErrOutside
		}
	}
	pts := geo.Simplify(t.Points, simplifyM)
	total := geo.CumulativeDistance(pts)[len(pts)-1]
	if total < minTrackM {
		return routes.Content{}, ErrShort
	}
	split := math.Max(legM, total/(routes.MaxAnchors-2))
	legs, err := im.Router.Track(ctx, pts, split)
	if err != nil {
		return routes.Content{}, err
	}
	c := routes.Content{Profile: "hike", Legs: legs}
	for i, l := range legs {
		first := l.Coordinates[0]
		c.Anchors = append(c.Anchors, routes.Anchor{Lon: first[0], Lat: first[1]})
		if i == len(legs)-1 {
			last := l.Coordinates[len(l.Coordinates)-1]
			c.Anchors = append(c.Anchors, routes.Anchor{Lon: last[0], Lat: last[1]})
		}
		// Edits of a track with alpine parts must route over them too.
		if l.SAC.Grade > 3 {
			c.Profile = "alpine"
		}
	}
	return c, nil
}

// Source says where tracks come from, for skipping repeated imports.
type Source struct {
	Kind string // gpx, kml, tcx, fit, komoot, recorded (with the app)
	Ref  string // e.g. the Komoot tour id; "" for files
}

// Route imports a track as a private route.
func (im *Importer) Route(ctx context.Context, owner uuid.UUID, t Track, src Source) (routes.Route, error) {
	c, err := im.Content(ctx, t)
	if err != nil {
		return routes.Route{}, err
	}
	r, err := im.Routes.Create(ctx, owner, routes.Meta{Title: title(t.Name), Visibility: "private"}, c)
	if err != nil {
		return routes.Route{}, err
	}
	if err := im.Routes.SetSource(ctx, uuid.MustParse(r.ID), src.Kind, src.Ref); err != nil {
		_ = im.Routes.Delete(ctx, uuid.MustParse(r.ID))
		return routes.Route{}, err
	}
	return r, nil
}

// Skipped is a track that was not imported, and why.
type Skipped struct {
	Name   string `json:"name"`
	Reason string `json:"reason" enum:"outside,short,elevation,duplicate,other"`
}

// Journey imports tracks as the stages of a new private journey. Tracks that
// cannot be imported become stages without a route and are reported.
func (im *Importer) Journey(ctx context.Context, owner uuid.UUID, name string, tracks []Track) (journeys.Journey, []Skipped, error) {
	j, err := im.Journeys.Create(ctx, owner, journeys.Meta{Title: title(name), Visibility: "private"})
	if err != nil {
		return j, nil, err
	}
	jid := uuid.MustParse(j.ID)
	var skipped []Skipped
	for _, t := range tracks {
		if err := im.Journeys.AddStage(ctx, jid, owner, journeys.NewStage{Title: title(t.Name)}); err != nil {
			return j, skipped, err
		}
		c, err := im.Content(ctx, t)
		if err != nil {
			skipped = append(skipped, Skipped{Name: t.Name, Reason: Reason(err)})
			continue
		}
		j, err = im.Journeys.Get(ctx, jid)
		if err != nil {
			return j, skipped, err
		}
		stage := uuid.MustParse(j.StageList[len(j.StageList)-1].ID)
		if _, err := im.Journeys.SetStageRoute(ctx, jid, stage, owner, title(t.Name), c); err != nil {
			return j, skipped, err
		}
	}
	j, err = im.Journeys.Get(ctx, jid)
	return j, skipped, err
}

// Join makes one track of several, in order (e.g. the days of a multi-day
// recording imported as one route).
func Join(name string, tracks []Track) Track {
	out := Track{Name: name}
	for _, t := range tracks {
		out.Points = append(out.Points, t.Points...)
	}
	out.Points = clean(out.Points)
	return out
}

// Reason classifies an import error for the report.
func Reason(err error) string {
	switch {
	case errors.Is(err, ErrOutside):
		return "outside"
	case errors.Is(err, ErrShort):
		return "short"
	case errors.Is(err, routing.ErrElevation):
		return "elevation"
	case errors.Is(err, routes.ErrDuplicate):
		return "duplicate"
	}
	return "other"
}

// title shortens a track name to a valid title.
func title(name string) string {
	name = strings.Join(strings.Fields(name), " ")
	if name == "" {
		name = "Import"
	}
	if r := []rune(name); len(r) > 120 {
		name = string(r[:120])
	}
	return name
}
