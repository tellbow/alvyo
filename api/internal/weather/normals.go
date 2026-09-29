package weather

import (
	"bufio"
	"bytes"
	"embed"
	"fmt"
	"math"
	"strconv"
	"strings"
	"sync"

	"golang.org/x/text/encoding/charmap"

	"github.com/tellbow/alvyo/swiss/geo"
	"github.com/tellbow/alvyo/swiss/lv95"
)

// MeteoSwiss's climate normals 1991–2020 per station (open data,
// https://data.geo.admin.ch/ch.meteoschweiz.klima/normwerte/normwerte.zip):
// the mean lowest and highest temperature of a day, precipitation and days
// with at least 1 mm, by month. Updated once a decade.
//
//go:embed normals/*.txt
var normalFiles embed.FS

// Lapse is how much colder it is per metre up (°C), to carry a station's
// temperatures to a place's height.
const Lapse = 0.0065

// Climate is what is usual at a place in a month.
type Climate struct {
	Month int `json:"month" minimum:"1" maximum:"12"`
	// Station is where the temperatures were measured (their height is
	// carried to the place's); RainStation where the precipitation was.
	Station     string  `json:"station"`
	Height      float64 `json:"height" doc:"The station's, metres"`
	RainStation string  `json:"rain_station"`
	MinC        float64 `json:"min_c" doc:"Mean lowest temperature of a day, °C, at the place's height"`
	MaxC        float64 `json:"max_c" doc:"Mean highest temperature of a day, °C, at the place's height"`
	RainMM      float64 `json:"rain_mm" doc:"Mean precipitation of the month, mm"`
	RainDays    float64 `json:"rain_days" doc:"Mean days of the month with at least 1 mm"`
}

type normalStation struct {
	name    string
	height  float64
	at      geo.Point
	byMonth [12]float64
}

var (
	normalsOnce sync.Once
	normals     map[string][]normalStation // by parameter
	normalsErr  error
)

func loadNormals() {
	normals = map[string][]normalStation{}
	for _, p := range []string{"tre2dymn", "tre2dymx", "rre150m0", "rsd010m0"} {
		raw, err := normalFiles.ReadFile("normals/" + p + ".txt")
		if err != nil {
			normalsErr = err
			return
		}
		if normals[p], err = parseNormals(raw); err != nil {
			normalsErr = fmt.Errorf("weather: normals %s: %w", p, err)
			return
		}
	}
}

// parseNormals reads a table: station, height, «E / N» in LV95, period,
// January to December, year; separated by tabs, in Latin-1.
func parseNormals(raw []byte) ([]normalStation, error) {
	var out []normalStation
	s := bufio.NewScanner(charmap.ISO8859_1.NewDecoder().Reader(bytes.NewReader(raw)))
	for s.Scan() {
		f := strings.Split(strings.TrimRight(s.Text(), "\r"), "\t")
		if len(f) < 16 || f[0] == "Station" {
			continue
		}
		height, err := strconv.ParseFloat(f[1], 64)
		if err != nil {
			continue
		}
		var e, n float64
		if _, err := fmt.Sscanf(f[2], "%f / %f", &e, &n); err != nil {
			continue
		}
		st := normalStation{name: f[0], height: height}
		st.at.Lon, st.at.Lat = lv95.ToWGS84(e, n)
		ok := true
		for m := range 12 {
			v, err := strconv.ParseFloat(f[4+m], 64)
			if err != nil {
				ok = false // a month without a value: the station is left out
				break
			}
			st.byMonth[m] = v
		}
		if ok {
			out = append(out, st)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no stations")
	}
	return out, s.Err()
}

// nearest is the station most like the place: distance plus, where height
// matters, 10 m per metre of height difference; within maxM.
func nearest(stations []normalStation, here geo.Point, height float64, heightMatters bool, maxM float64) (normalStation, bool) {
	best, bestScore := -1, math.Inf(1)
	for i, st := range stations {
		d := geo.Distance(here, st.at)
		if d > maxM {
			continue
		}
		score := d
		if heightMatters {
			score += 10 * math.Abs(st.height-height)
		}
		if score < bestScore {
			best, bestScore = i, score
		}
	}
	if best < 0 {
		return normalStation{}, false
	}
	return stations[best], true
}

// ClimateAt returns the climate normals of month (1–12) at a place: the
// temperatures of the station most like it within 40 km, carried to its
// height, and the precipitation of the nearest station within 20 km.
// False outside the stations' reach (across the border).
func ClimateAt(lon, lat, height float64, month int) (Climate, bool) {
	normalsOnce.Do(loadNormals)
	if normalsErr != nil || month < 1 || month > 12 {
		return Climate{}, false
	}
	here := geo.Point{Lon: lon, Lat: lat}
	lo, ok1 := nearest(normals["tre2dymn"], here, height, true, 40_000)
	hi, ok2 := nearest(normals["tre2dymx"], here, height, true, 40_000)
	rain, ok3 := nearest(normals["rre150m0"], here, height, false, 20_000)
	days, ok4 := nearest(normals["rsd010m0"], here, height, false, 20_000)
	if !ok1 || !ok2 || !ok3 || !ok4 {
		return Climate{}, false
	}
	m := month - 1
	round := func(v float64) float64 { return math.Round(v*10) / 10 }
	return Climate{
		Month: month, Station: lo.name, Height: lo.height, RainStation: rain.name,
		MinC:     round(lo.byMonth[m] - Lapse*(height-lo.height)),
		MaxC:     round(hi.byMonth[m] - Lapse*(height-hi.height)),
		RainMM:   rain.byMonth[m],
		RainDays: days.byMonth[m],
	}, true
}
