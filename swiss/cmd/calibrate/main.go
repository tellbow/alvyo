// Command calibrate compares our distance, ascent and Swiss hiking time with
// the official values of SchweizMobil stages (testdata/reference_stages.json)
// and prints Markdown tables for docs/hiking-time.md.
//
// Elevations come from the geo.admin.ch profile service, as in the API, and
// are cached (-cache) so that variants can be compared offline:
//
//	go run ./cmd/calibrate -cache /tmp/alvyo-calibrate > report.md
//
// With -swissalti3d, they come from swissALTI3D tiles on disk instead
// (infra/data-import/swissalti3d.py).
//
// With -graphhopper, each stage is also planned as a person would: routed
// through GraphHopper between points of the official line every -anchor-km;
// and timed by GraphHopper's own profiles for isochrones (hike_time), which
// time the ways by slope like the Swiss formula.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"iter"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/tellbow/alvyo/swiss/elevation"
	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/stats"
)

type stage struct {
	Route          int    `json:"route"`
	Stage          int    `json:"stage"`
	From           string `json:"from"`
	To             string `json:"to"`
	DistanceM      float64
	AscentM        float64 `json:"ascent_m"`
	DescentM       float64 `json:"descent_m"`
	Minutes        float64 `json:"minutes"`
	MinutesReverse float64 `json:"minutes_reverse"`
	Line           string  `json:"line"`
}

func (s *stage) UnmarshalJSON(b []byte) error {
	type plain stage
	var aux struct {
		plain
		DistanceM float64 `json:"distance_m"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	*s = stage(aux.plain)
	s.DistanceM = aux.DistanceM
	return nil
}

// decode reads a Google encoded polyline (lat, lon; precision 1e5).
func decode(s string) []geo.Point {
	var pts []geo.Point
	lat, lon, i := 0, 0, 0
	next := func() int {
		v, shift := 0, 0
		for {
			b := int(s[i]) - 63
			i++
			v |= (b & 0x1f) << shift
			shift += 5
			if b < 0x20 {
				break
			}
		}
		if v&1 != 0 {
			return ^(v >> 1)
		}
		return v >> 1
	}
	for i < len(s) {
		lat += next()
		lon += next()
		pts = append(pts, geo.Point{Lon: float64(lon) / 1e5, Lat: float64(lat) / 1e5})
	}
	return pts
}

// maxVertexSpacing densifies lines like the API (api/internal/routing).
const maxVertexSpacing = 20

func main() {
	ref := flag.String("ref", "testdata/reference_stages.json", "reference stages")
	cache := flag.String("cache", filepath.Join(os.TempDir(), "alvyo-calibrate"), "elevation cache directory")
	gh := flag.String("graphhopper", "", "GraphHopper URL, e.g. http://localhost:8989, to also plan each stage")
	anchorKm := flag.Float64("anchor-km", 5, "distance between planning points along the official line")
	alti := flag.String("swissalti3d", "", "directory of swissALTI3D tiles to take the heights from instead of geo.admin")
	flag.Parse()

	var doc struct {
		Source string  `json:"source"`
		Stages []stage `json:"stages"`
	}
	b, err := os.ReadFile(*ref)
	if err != nil {
		fail(err)
	}
	if err := json.Unmarshal(b, &doc); err != nil {
		fail(err)
	}
	if err := os.MkdirAll(*cache, 0o755); err != nil {
		fail(err)
	}
	var sampler elevation.Sampler = &elevation.GeoAdmin{UserAgent: "alvyo-calibrate (+https://github.com/tellbow/alvyo)"}
	source := ""
	if *alti != "" {
		sampler, source = &elevation.SwissALTI3D{Dir: *alti}, "swissalti3d-"
	}

	type prepared struct {
		s   stage
		pts []geo.Point
		ele []float64
	}
	var all []prepared
	for _, s := range doc.Stages {
		pts, _ := geo.Densify(decode(s.Line), maxVertexSpacing)
		ele, err := cachedElevation(*cache, source+"stage", s, pts, sampler)
		if err != nil {
			fail(fmt.Errorf("stage %d.%d: %w", s.Route, s.Stage, err))
		}
		all = append(all, prepared{s, pts, ele})
	}

	fmt.Printf("Source: %s. %d stages.\n\n", doc.Source, len(all))

	// Variants of the profile step and ascent threshold.
	fmt.Println("| Step | Ascent threshold | Time within ±10 % | Time mean | Time worst | Ascent within ±10 % | Ascent mean | Ascent worst | Descent mean |")
	fmt.Println("|---|---|---|---|---|---|---|---|---|")
	for _, step := range []float64{10, 20, 25, 50} {
		for _, th := range []float64{0, 1, 2, 3} {
			var tr, ar, dr []float64
			for _, p := range all {
				st := stats.ComputeWith(p.pts, p.ele, step, th)
				tr = append(tr, minutesOf(st.Duration)/p.s.Minutes, minutesOf(st.DurationReverse)/p.s.MinutesReverse)
				ar = append(ar, st.AscentM/p.s.AscentM)
				dr = append(dr, st.DescentM/p.s.DescentM)
			}
			mark := ""
			if step == stats.ProfileStep && th == stats.AscentThreshold {
				mark = " (current)"
			}
			fmt.Printf("| %.0f m%s | %.0f m | %s | %s | %s | %s | %s | %s | %s |\n", step, mark, th,
				within(tr, 0.1), pct(mean(tr)), pct(worst(tr)), within(ar, 0.1), pct(mean(ar)), pct(worst(ar)), pct(mean(dr)))
		}
	}

	fmt.Println("\nPer stage with the current settings (deviation from the official value):")
	fmt.Println()
	fmt.Println("| Stage | From – to | km | Δ km | ↑ m | Δ ↑ | Time | Δ time | Δ way back |")
	fmt.Println("|---|---|---|---|---|---|---|---|---|")
	sort.Slice(all, func(i, j int) bool {
		a, b := all[i].s, all[j].s
		return a.Route < b.Route || (a.Route == b.Route && a.Stage < b.Stage)
	})
	for _, p := range all {
		st := stats.Compute(p.pts, p.ele)
		s := p.s
		fmt.Printf("| %d.%02d | %s – %s | %.1f | %s | %.0f | %s | %s | %s | %s |\n", s.Route, s.Stage,
			s.From, s.To, s.DistanceM/1000, pct(st.DistanceM/s.DistanceM), s.AscentM, pct(st.AscentM/s.AscentM),
			hm(s.Minutes), pct(minutesOf(st.Duration)/s.Minutes), pct(minutesOf(st.DurationReverse)/s.MinutesReverse))
	}

	if *gh == "" {
		return
	}
	fmt.Printf("\nPlanned through GraphHopper with a point every %.0f km of the official line (current settings):\n\n", *anchorKm)
	fmt.Println("| Stage | Points | Δ km | Δ ↑ | Δ time |")
	fmt.Println("|---|---|---|---|---|")
	var dr, ar, tr []float64
	for _, p := range all {
		anchors := anchorsEvery(decode(p.s.Line), *anchorKm*1000)
		line, err := plan(*gh, anchors)
		if err != nil {
			fmt.Printf("| %d.%02d | %d | %v | | |\n", p.s.Route, p.s.Stage, len(anchors), err)
			continue
		}
		dense, _ := geo.Densify(line, maxVertexSpacing)
		ele, err := cachedElevation(*cache, source+"planned", p.s, dense, sampler)
		if err != nil {
			fail(err)
		}
		st := stats.Compute(dense, ele)
		d, a, t := st.DistanceM/p.s.DistanceM, st.AscentM/p.s.AscentM, minutesOf(st.Duration)/p.s.Minutes
		dr, ar, tr = append(dr, d), append(ar, a), append(tr, t)
		fmt.Printf("| %d.%02d | %d | %s | %s | %s |\n", p.s.Route, p.s.Stage, len(anchors), pct(d), pct(a), pct(t))
	}
	fmt.Printf("\nDistance within ±5 %%: %s (mean %s). Time within ±10 %%: %s (mean %s, worst %s). Ascent within ±10 %%: %s (mean %s).\n",
		within(dr, 0.05), pct(mean(dr)), within(tr, 0.1), pct(mean(tr)), pct(worst(tr)), within(ar, 0.1), pct(mean(ar)))

	// The time profiles of «Wie weit komme ich?» (requirement 65), along the
	// official line both ways, against the official times.
	fmt.Println("\nTimed by GraphHopper's hike_time (alpine_time where it finds no way), a point every 2 km:")
	fmt.Println()
	fmt.Println("| Stage | Time | Δ time | Δ way back |")
	fmt.Println("|---|---|---|---|")
	tr = nil
	for _, p := range all {
		anchors := anchorsEvery(decode(p.s.Line), 2000)
		there, err1 := timed(*gh, slices.All(anchors))
		back, err2 := timed(*gh, slices.Backward(anchors))
		if err := errors.Join(err1, err2); err != nil {
			fmt.Printf("| %d.%02d | %v | | |\n", p.s.Route, p.s.Stage, err)
			continue
		}
		t, tb := there/p.s.Minutes, back/p.s.MinutesReverse
		tr = append(tr, t, tb)
		fmt.Printf("| %d.%02d | %s | %s | %s |\n", p.s.Route, p.s.Stage, hm(p.s.Minutes), pct(t), pct(tb))
	}
	fmt.Printf("\nTime within ±10 %%: %s (mean %s, median %s, worst %s).\n", within(tr, 0.1), pct(mean(tr)), pct(median(tr)), pct(worst(tr)))
}

// timed is GraphHopper's time in minutes from anchor to anchor by the time
// profiles.
func timed(url string, anchors iter.Seq2[int, geo.Point]) (float64, error) {
	var prev *geo.Point
	total := 0.0
	for _, a := range anchors {
		if prev != nil {
			var ms float64
			var err error
			for _, profile := range []string{"hike_time", "alpine_time"} {
				if _, ms, err = route(url, *prev, a, profile); err == nil {
					break
				}
			}
			if err != nil {
				return 0, err
			}
			total += ms / 60000
		}
		prev = &a
	}
	return total, nil
}

// anchorsEvery picks points of line about every step metres, with both ends.
func anchorsEvery(line []geo.Point, step float64) []geo.Point {
	dist := geo.CumulativeDistance(line)
	out := []geo.Point{line[0]}
	next := step
	for i, d := range dist {
		if d >= next && dist[len(dist)-1]-d > step/2 {
			out = append(out, line[i])
			next = d + step
		}
	}
	return append(out, line[len(line)-1])
}

// plan routes between consecutive anchors like the planner (profile hike,
// alpine where hike finds no way).
func plan(url string, anchors []geo.Point) ([]geo.Point, error) {
	var line []geo.Point
	for i := 1; i < len(anchors); i++ {
		var leg []geo.Point
		var err error
		for _, profile := range []string{"hike", "alpine"} {
			if leg, _, err = route(url, anchors[i-1], anchors[i], profile); err == nil {
				break
			}
		}
		if err != nil {
			return nil, err
		}
		if len(line) > 0 {
			leg = leg[1:]
		}
		line = append(line, leg...)
	}
	return line, nil
}

// route returns GraphHopper's path and its time in milliseconds. The time
// profiles have no CH: they are searched without it.
func route(url string, from, to geo.Point, profile string) ([]geo.Point, float64, error) {
	body, _ := json.Marshal(map[string]any{
		"points": [][2]float64{{from.Lon, from.Lat}, {to.Lon, to.Lat}}, "profile": profile,
		"points_encoded": false, "instructions": false, "ch.disable": strings.HasSuffix(profile, "_time"),
	})
	resp, err := http.Post(strings.TrimSuffix(url, "/")+"/route", "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, 0, err
	}
	defer func() { _ = resp.Body.Close() }()
	var r struct {
		Paths []struct {
			Time   float64 `json:"time"`
			Points struct {
				Coordinates [][]float64 `json:"coordinates"`
			} `json:"points"`
		} `json:"paths"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil || resp.StatusCode != http.StatusOK || len(r.Paths) == 0 {
		return nil, 0, fmt.Errorf("graphhopper %s: HTTP %d", profile, resp.StatusCode)
	}
	pts := make([]geo.Point, len(r.Paths[0].Points.Coordinates))
	for i, c := range r.Paths[0].Points.Coordinates {
		pts[i] = geo.Point{Lon: c[0], Lat: c[1]}
	}
	return pts, r.Paths[0].Time, nil
}

// cachedElevation samples pts once and keeps the result in dir.
func cachedElevation(dir, kind string, s stage, pts []geo.Point, g elevation.Sampler) ([]float64, error) {
	file := filepath.Join(dir, fmt.Sprintf("%s-%d-%02d-%d.json", kind, s.Route, s.Stage, len(pts)))
	if b, err := os.ReadFile(file); err == nil {
		var ele []float64
		if json.Unmarshal(b, &ele) == nil && len(ele) == len(pts) {
			return ele, nil
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	ele, err := g.Sample(ctx, pts)
	if err != nil {
		return nil, err
	}
	b, _ := json.Marshal(ele)
	return ele, os.WriteFile(file, b, 0o644)
}

func minutesOf(d time.Duration) float64 { return d.Minutes() }

func mean(xs []float64) float64 {
	t := 0.0
	for _, x := range xs {
		t += x
	}
	return t / float64(len(xs))
}

func median(xs []float64) float64 {
	s := slices.Sorted(slices.Values(xs))
	if len(s) == 0 {
		return math.NaN()
	}
	if len(s)%2 == 1 {
		return s[len(s)/2]
	}
	return (s[len(s)/2-1] + s[len(s)/2]) / 2
}

// worst is the ratio furthest from 1.
func worst(xs []float64) float64 {
	w := 1.0
	for _, x := range xs {
		if math.Abs(x-1) > math.Abs(w-1) {
			w = x
		}
	}
	return w
}

func within(xs []float64, tol float64) string {
	n := 0
	for _, x := range xs {
		if math.Abs(x-1) <= tol {
			n++
		}
	}
	return fmt.Sprintf("%d/%d", n, len(xs))
}

// pct shows a ratio as a signed percentage deviation.
func pct(r float64) string { return fmt.Sprintf("%+.1f %%", (r-1)*100) }

func hm(m float64) string {
	r := int(math.Round(m))
	return fmt.Sprintf("%d h %02d", r/60, r%60)
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "calibrate:", strings.TrimSpace(err.Error()))
	os.Exit(1)
}
