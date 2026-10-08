// Package weather holds MeteoSwiss's local forecast (open data): for every
// postcode, weather station and selected point in the mountains the lowest
// and highest temperature, the precipitation and the weather symbol of the
// next nine days; and the climate normals of its stations (normals.go). The
// latest run is loaded into memory once an hour; points along a route take
// the forecast point nearby of the most similar height.
package weather

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/text/encoding/charmap"

	"github.com/tellbow/alvyo/swiss/geo"
)

// STACURL is the collection of MeteoSwiss's local forecasts on
// data.geo.admin.ch.
const STACURL = "https://data.geo.admin.ch/api/stac/v1/collections/ch.meteoschweiz.ogd-local-forecasting"

// The daily values used (local days).
const (
	paramMin    = "tre200pn"
	paramMax    = "tre200px"
	paramRain   = "rka150p0"
	paramRain10 = "rreq10p0"
	paramRain90 = "rreq90p0"
	// MeteoSwiss's pictogram number for the day (1–42); read when a run has it.
	paramSymbol = "jp2000d0"
)

var params = []string{paramMin, paramMax, paramRain, paramRain10, paramRain90}

// ErrNoForecast means no forecast has been loaded (yet).
var ErrNoForecast = errors.New("weather: no forecast loaded")

// ForecastPoint is a place MeteoSwiss forecasts for.
type ForecastPoint struct {
	Name   string  `json:"name"`
	Height float64 `json:"height" doc:"metres"`
	Lon    float64 `json:"lon"`
	Lat    float64 `json:"lat"`
	key    string
}

// ForecastDay is the forecast of one day at a point.
type ForecastDay struct {
	Date string  `json:"date" format:"date"`
	MinC float64 `json:"min_c" doc:"Lowest temperature, °C"`
	MaxC float64 `json:"max_c" doc:"Highest temperature, °C"`
	// Precipitation in mm, and the range it likely stays in (10 % and 90 %
	// quantiles).
	RainMM   float64 `json:"rain_mm"`
	RainLoMM float64 `json:"rain_lo_mm"`
	RainHiMM float64 `json:"rain_hi_mm"`
	// Symbol is MeteoSwiss's pictogram number for the daytime (1–42);
	// its meaning is in their list of weather symbols.
	Symbol int `json:"symbol,omitempty"`
}

// Forecast is the latest local forecast.
type Forecast struct {
	URL       string       // defaults to STACURL
	Client    *http.Client // defaults to a 60 s timeout
	UserAgent string

	mu     sync.RWMutex
	run    time.Time
	points []ForecastPoint
	days   map[string][]ForecastDay // by point key
}

// Run returns when the loaded forecast was made; zero before the first.
func (f *Forecast) Run() time.Time {
	f.mu.RLock()
	defer f.mu.RUnlock()
	return f.run
}

// Keep refreshes the forecast every interval until ctx ends; failures are
// logged and the old forecast kept.
func (f *Forecast) Keep(ctx context.Context, interval time.Duration) {
	for {
		if err := f.Refresh(ctx); err != nil && ctx.Err() == nil {
			slog.WarnContext(ctx, "weather refresh failed", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// At returns the forecast point near (lon, lat) most like it: within 15 km,
// the one where distance plus 10 m per metre of height difference is
// least (temperature follows height more than distance); with its days.
func (f *Forecast) At(lon, lat, height float64) (ForecastPoint, []ForecastDay, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	if len(f.points) == 0 {
		return ForecastPoint{}, nil, ErrNoForecast
	}
	here := geo.Point{Lon: lon, Lat: lat}
	best, bestScore := -1, math.Inf(1)
	for i, p := range f.points {
		if math.Abs(p.Lat-lat) > 0.15 || math.Abs(p.Lon-lon) > 0.2 {
			continue
		}
		d := geo.Distance(here, geo.Point{Lon: p.Lon, Lat: p.Lat})
		if d > 15_000 {
			continue
		}
		if s := d + 10*math.Abs(p.Height-height); s < bestScore {
			best, bestScore = i, s
		}
	}
	if best < 0 {
		return ForecastPoint{}, nil, ErrNoForecast
	}
	p := f.points[best]
	return p, f.days[p.key], nil
}

// Refresh loads the latest run with all daily values, unless it is loaded.
func (f *Forecast) Refresh(ctx context.Context) error {
	run, files, err := f.latest(ctx)
	if err != nil {
		return err
	}
	if !run.After(f.Run()) {
		return nil
	}
	points, err := f.readPoints(ctx)
	if err != nil {
		return err
	}
	values := map[string]map[string]map[string]float64{} // param → point → date → value
	for _, p := range params {
		if values[p], err = f.readParam(ctx, files[p], p); err != nil {
			return err
		}
	}
	if href := files[paramSymbol]; href != "" {
		if values[paramSymbol], err = f.readParam(ctx, href, paramSymbol); err != nil {
			return err
		}
	}
	days := map[string][]ForecastDay{}
	for key, byDate := range values[paramMax] {
		dates := make([]string, 0, len(byDate))
		for d := range byDate {
			dates = append(dates, d)
		}
		sort.Strings(dates)
		for _, d := range dates {
			// Without its minimum or rain the day would show 0 °C and 0 mm.
			_, okMin := values[paramMin][key][d]
			_, okRain := values[paramRain][key][d]
			if !okMin || !okRain {
				continue
			}
			days[key] = append(days[key], ForecastDay{
				Date: d, MinC: values[paramMin][key][d], MaxC: byDate[d],
				RainMM: values[paramRain][key][d], RainLoMM: values[paramRain10][key][d], RainHiMM: values[paramRain90][key][d],
				Symbol: int(values[paramSymbol][key][d]),
			})
		}
	}
	f.mu.Lock()
	f.run, f.points, f.days = run, points, days
	f.mu.Unlock()
	return nil
}

// latest finds the newest run that has every daily file, and their
// addresses by parameter.
func (f *Forecast) latest(ctx context.Context) (time.Time, map[string]string, error) {
	var items struct {
		Features []struct {
			ID     string `json:"id"`
			Assets map[string]struct {
				Href string `json:"href"`
			} `json:"assets"`
		} `json:"features"`
	}
	if err := f.getJSON(ctx, f.base()+"/items?limit=20", &items); err != nil {
		return time.Time{}, nil, err
	}
	var best time.Time
	var bestFiles map[string]string
	for _, it := range items.Features {
		byRun := map[string]map[string]string{}
		for name, a := range it.Assets {
			// vnut12.lssw.202609281800.tre200px.csv
			parts := strings.Split(name, ".")
			if len(parts) != 5 {
				continue
			}
			if byRun[parts[2]] == nil {
				byRun[parts[2]] = map[string]string{}
			}
			byRun[parts[2]][parts[3]] = a.Href
		}
		for r, files := range byRun {
			t, err := time.Parse("200601021504", r)
			if err != nil || !t.After(best) || !hasAll(files) {
				continue
			}
			best, bestFiles = t, files
		}
	}
	if bestFiles == nil {
		return time.Time{}, nil, fmt.Errorf("weather: no complete run")
	}
	return best, bestFiles, nil
}

func hasAll(files map[string]string) bool {
	for _, p := range params {
		if files[p] == "" {
			return false
		}
	}
	return true
}

func (f *Forecast) base() string {
	if f.URL != "" {
		return strings.TrimSuffix(f.URL, "/")
	}
	return STACURL
}

// readPoints reads the points' names, heights and positions.
func (f *Forecast) readPoints(ctx context.Context) ([]ForecastPoint, error) {
	var col struct {
		Assets map[string]struct {
			Href string `json:"href"`
		} `json:"assets"`
	}
	if err := f.getJSON(ctx, f.base(), &col); err != nil {
		return nil, err
	}
	href := col.Assets["ogd-local-forecasting_meta_point.csv"].Href
	if href == "" {
		return nil, fmt.Errorf("weather: no point list")
	}
	var out []ForecastPoint
	err := f.readCSV(ctx, href, func(head, row []string) {
		col := func(name string) string {
			for i, h := range head {
				if h == name && i < len(row) {
					return row[i]
				}
			}
			return ""
		}
		num := func(name string) float64 {
			v, _ := strconv.ParseFloat(col(name), 64)
			return v
		}
		p := ForecastPoint{
			Name: col("point_name"), Height: num("point_height_masl"),
			Lon: num("point_coordinates_wgs84_lon"), Lat: num("point_coordinates_wgs84_lat"),
			key: col("point_type_id") + "/" + col("point_id"),
		}
		if p.Lon != 0 && p.Lat != 0 {
			out = append(out, p)
		}
	})
	return out, err
}

// readParam reads a daily file: point_id;point_type_id;Date;value.
func (f *Forecast) readParam(ctx context.Context, href, param string) (map[string]map[string]float64, error) {
	out := map[string]map[string]float64{}
	err := f.readCSV(ctx, href, func(_, row []string) {
		if len(row) < 4 || len(row[2]) < 8 {
			return
		}
		v, err := strconv.ParseFloat(row[3], 64)
		if err != nil {
			return
		}
		key := row[1] + "/" + row[0]
		if out[key] == nil {
			out[key] = map[string]float64{}
		}
		d := row[2]
		out[key][d[0:4]+"-"+d[4:6]+"-"+d[6:8]] = v
	})
	if err == nil && len(out) == 0 {
		err = fmt.Errorf("weather: %s is empty", param)
	}
	return out, err
}

// readCSV reads a Latin-1 CSV separated by semicolons (quoted fields do not
// occur in the files read).
func (f *Forecast) readCSV(ctx context.Context, href string, each func(head, row []string)) error {
	body, err := f.get(ctx, href)
	if err != nil {
		return err
	}
	defer func() { _ = body.Close() }()
	s := bufio.NewScanner(charmap.ISO8859_1.NewDecoder().Reader(body))
	s.Buffer(make([]byte, 64*1024), 1<<20)
	var head []string
	for s.Scan() {
		row := strings.Split(strings.TrimRight(s.Text(), "\r"), ";")
		if head == nil {
			head = row
			continue
		}
		each(head, row)
	}
	return s.Err()
}

func (f *Forecast) getJSON(ctx context.Context, url string, v any) error {
	body, err := f.get(ctx, url)
	if err != nil {
		return err
	}
	defer func() { _ = body.Close() }()
	return json.NewDecoder(io.LimitReader(body, 16<<20)).Decode(v)
}

func (f *Forecast) get(ctx context.Context, url string) (io.ReadCloser, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if f.UserAgent != "" {
		req.Header.Set("User-Agent", f.UserAgent)
	}
	client := f.Client
	if client == nil {
		client = &http.Client{Timeout: 60 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("weather: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		_ = resp.Body.Close()
		return nil, fmt.Errorf("weather: %s: status %d", url, resp.StatusCode)
	}
	return resp.Body, nil
}
