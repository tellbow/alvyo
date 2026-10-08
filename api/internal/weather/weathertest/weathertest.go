// Package weathertest serves a MeteoSwiss local forecast for tests.
package weathertest

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"golang.org/x/text/encoding/charmap"
)

// Point is a forecast point: type/id as in MeteoSwiss's files.
type Point struct {
	Type, ID, Name string
	Height         float64
	Lon, Lat       float64
}

// Params are the daily values the forecast reads, with the value served
// for every point and day.
var Params = map[string]string{
	"tre200pn": "4.5", "tre200px": "12.0", "rka150p0": "3.2", "rreq10p0": "0.4", "rreq90p0": "9.8", "jp2000d0": "6",
}

// Server serves the collection at /c (with the point list), its items (one,
// with a complete run at 18:00 and an incomplete one at 19:00) and the
// files for days; files counts the downloads of daily values. skip leaves
// out days of a parameter ("tre200pn/2026-09-29").
func Server(t *testing.T, points []Point, days []string, skip ...string) (srv *httptest.Server, files *int) {
	files = new(int)
	mux := http.NewServeMux()
	srv = httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	mux.HandleFunc("/c", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprintf(w, `{"assets":{"ogd-local-forecasting_meta_point.csv":{"href":"%s/points.csv"}}}`, srv.URL)
	})
	mux.HandleFunc("/c/items", func(w http.ResponseWriter, _ *http.Request) {
		var assets []string
		for p := range Params {
			assets = append(assets, fmt.Sprintf(`"vnut12.lssw.202609281800.%s.csv":{"href":"%s/%s.csv"}`, p, srv.URL, p))
		}
		assets = append(assets, fmt.Sprintf(`"vnut12.lssw.202609281900.tre200px.csv":{"href":"%s/tre200px.csv"}`, srv.URL))
		_, _ = fmt.Fprintf(w, `{"features":[{"id":"20260928-ch","assets":{%s}}]}`, strings.Join(assets, ","))
	})
	mux.HandleFunc("/points.csv", func(w http.ResponseWriter, _ *http.Request) {
		var b strings.Builder
		b.WriteString("point_id;point_type_id;station_abbr;postal_code;point_name;point_type_de;point_type_fr;point_type_it;point_type_en;point_height_masl;point_coordinates_lv95_east;point_coordinates_lv95_north;point_coordinates_wgs84_lat;point_coordinates_wgs84_lon\r\n")
		for _, p := range points {
			fmt.Fprintf(&b, "%s;%s;;;%s;;;;;%.1f;;;%.6f;%.6f\r\n", p.ID, p.Type, p.Name, p.Height, p.Lat, p.Lon)
		}
		latin1, err := charmap.ISO8859_1.NewEncoder().String(b.String())
		if err != nil {
			t.Error(err)
		}
		_, _ = w.Write([]byte(latin1))
	})
	for p, v := range Params {
		mux.HandleFunc("/"+p+".csv", func(w http.ResponseWriter, _ *http.Request) {
			*files++
			_, _ = fmt.Fprintf(w, "point_id;point_type_id;Date;%s\r\n", p)
			for _, pt := range points {
				for _, d := range days {
					if slices.Contains(skip, p+"/"+d) {
						continue
					}
					_, _ = fmt.Fprintf(w, "%s;%s;%s0000;%s\r\n", pt.ID, pt.Type, strings.ReplaceAll(d, "-", ""), v)
				}
			}
		})
	}
	return srv, files
}
