// Package journeys stores multi-day and multi-week hikes: ordered stages,
// each with its own route.
package journeys

import (
	"math"
	"time"

	"github.com/tellbow/odysgeh/api/internal/places"
	"github.com/tellbow/odysgeh/api/internal/routes"
	"github.com/tellbow/odysgeh/swiss/geo"
)

// Continuity thresholds between the end of a stage and the start of the next.
const (
	gapOK      = 100  // metres: the same place
	gapWarning = 1000 // metres: probably a short walk to the station or hut
	// profilePoints bounds the combined elevation profile.
	profilePoints = 1500
	// suggestRadius: a stop or hut this close to a stage end is suggested as
	// its start or end place.
	suggestRadius = 400
)

// Meta is the descriptive part of a journey.
type Meta struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Visibility  string `json:"visibility" enum:"private,unlisted,public"`
}

// Summary is a journey in lists.
type Summary struct {
	ID            string `json:"id" format:"uuid"`
	OwnerUsername string `json:"owner_username"`
	Meta
	Stages     int       `json:"stages"`
	StagesDone int       `json:"stages_done"`
	DistanceM  float64   `json:"distance_m"`
	AscentM    float64   `json:"ascent_m"`
	DurationS  int       `json:"duration_s"`
	Version    int       `json:"version"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// StageRoute is the route of a stage as the journey page needs it.
type StageRoute struct {
	ID     string        `json:"id" format:"uuid"`
	Totals routes.Totals `json:"totals"`
	// Line is the route simplified for the overview map (lon, lat).
	Line  [][2]float64 `json:"line"`
	Start [2]float64   `json:"start"`
	End   [2]float64   `json:"end"`
}

// Gap describes how the stage connects to the previous one.
type Gap struct {
	Metres float64 `json:"metres"`
	// Status: ok (same place), warning (up to 1 km), gap, or transfer (a gap
	// the hiker covers by train, cable car … as noted on the stage).
	Status string `json:"status" enum:"ok,warning,gap,transfer"`
}

// Stage is one day (or part) of a journey.
type Stage struct {
	ID             string  `json:"id" format:"uuid"`
	Position       int     `json:"position"`
	Title          string  `json:"title"`
	PlannedDate    *string `json:"planned_date" format:"date"`
	Status         string  `json:"status" enum:"planned,done,skipped"`
	DoneOn         *string `json:"done_on" format:"date"`
	TransferBefore *string `json:"transfer_before" enum:"pt,cablecar,other"`
	Notes          string  `json:"notes"`
	// StartPlace and EndPlace are where the stage starts and ends (a stop, hut
	// …): chosen by the author, or else the nearest stop or hut (suggested).
	StartPlace          *places.Place `json:"start_place"`
	EndPlace            *places.Place `json:"end_place"`
	Accommodation       string        `json:"accommodation" doc:"Where the hiker sleeps after the stage"`
	AccommodationBooked bool          `json:"accommodation_booked"`
	Route               *StageRoute   `json:"route"`
	// Gap to the previous stage with a route; nil for the first one.
	Gap *Gap `json:"gap"`

	line [][3]float64 // full stage line (lon, lat, ele) for the profile
}

// Progress counts done stages (skipped stages do not count as remaining).
type Progress struct {
	StagesDone     int     `json:"stages_done"`
	StagesTotal    int     `json:"stages_total"`
	DistanceDoneM  float64 `json:"distance_done_m"`
	DistanceTotalM float64 `json:"distance_total_m"`
}

// Profile is the combined elevation profile of all stages, downsampled.
type Profile struct {
	Distance []float64 `json:"distance" doc:"Cumulative metres; gaps between stages are not counted"`
	// Points are [lon, lat, elevation] per profile sample.
	Points [][3]float64 `json:"points"`
	// Breaks[i] is the index where the i-th routed stage starts.
	Breaks []int `json:"breaks"`
}

// Journey is a journey with its stages and derived numbers.
type Journey struct {
	Summary
	OwnerID    string        `json:"-"`
	ShareToken string        `json:"-"`
	StageList  []Stage       `json:"stage_list"`
	Totals     routes.Totals `json:"totals"`
	Progress   Progress      `json:"progress"`
	Profile    Profile       `json:"profile"`
}

// derive fills gaps, totals, progress and the profile from the stages.
func (j *Journey) derive() {
	j.Totals = routes.Totals{EleMinM: math.Inf(1), EleMaxM: math.Inf(-1)}
	j.Progress = Progress{}
	var prev *StageRoute
	for i := range j.StageList {
		s := &j.StageList[i]
		if s.Status != "skipped" {
			j.Progress.StagesTotal++
		}
		if s.Status == "done" {
			j.Progress.StagesDone++
		}
		if s.Route == nil {
			continue
		}
		t := s.Route.Totals
		addTotals(&j.Totals, t)
		if s.Status != "skipped" {
			j.Progress.DistanceTotalM += t.DistanceM
		}
		if s.Status == "done" {
			j.Progress.DistanceDoneM += t.DistanceM
		}
		if prev != nil {
			d := geo.Distance(point(prev.End), point(s.Route.Start))
			s.Gap = &Gap{Metres: math.Round(d), Status: gapStatus(d, s.TransferBefore != nil)}
		}
		prev = s.Route
	}
	if math.IsInf(j.Totals.EleMinM, 1) {
		j.Totals.EleMinM, j.Totals.EleMaxM = 0, 0
	}
	j.Profile = profile(j.StageList)
}

func gapStatus(d float64, transfer bool) string {
	switch {
	case d <= gapOK:
		return "ok"
	case transfer:
		return "transfer"
	case d <= gapWarning:
		return "warning"
	default:
		return "gap"
	}
}

func addTotals(t *routes.Totals, s routes.Totals) {
	t.DistanceM += s.DistanceM
	t.AscentM += s.AscentM
	t.DescentM += s.DescentM
	t.DurationS += s.DurationS
	t.DurationReverseS += s.DurationReverseS
	t.EleMinM = min(t.EleMinM, s.EleMinM)
	t.EleMaxM = max(t.EleMaxM, s.EleMaxM)
	t.SACGrade = max(t.SACGrade, s.SACGrade)
	t.SACMax = max(t.SACMax, s.SACMax, s.SACGrade)
}

// profile joins the stage lines into one elevation profile. Each stage gets a
// share of the point budget proportional to its length, so stage breaks are
// exact and summits of every stage survive (LTTB keeps extremes).
func profile(stages []Stage) Profile {
	p := Profile{Distance: []float64{}, Points: [][3]float64{}, Breaks: []int{}}
	total := 0.0
	for _, s := range stages {
		if s.Route != nil {
			total += s.Route.Totals.DistanceM
		}
	}
	offset := 0.0
	for _, s := range stages {
		if s.Route == nil || len(s.line) < 2 {
			continue
		}
		pts := make([]geo.Point, len(s.line))
		ele := make([]float64, len(s.line))
		for i, c := range s.line {
			pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
			ele[i] = c[2]
		}
		dist := geo.CumulativeDistance(pts)
		budget := 20
		if total > 0 {
			budget = max(20, int(float64(profilePoints)*dist[len(dist)-1]/total))
		}
		p.Breaks = append(p.Breaks, len(p.Distance))
		for _, i := range geo.LTTB(dist, ele, budget) {
			p.Distance = append(p.Distance, math.Round(offset+dist[i]))
			p.Points = append(p.Points, [3]float64{s.line[i][0], s.line[i][1], math.Round(ele[i]*10) / 10})
		}
		offset += dist[len(dist)-1]
	}
	return p
}

func point(c [2]float64) geo.Point { return geo.Point{Lon: c[0], Lat: c[1]} }
