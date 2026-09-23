package places

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

// DefaultSearchURL is the geo.admin SearchServer.
const DefaultSearchURL = "https://api3.geo.admin.ch/rest/services/ech/SearchServer"

// GeoAdmin searches swisstopo's geographical names (swissNAMES3D: places,
// peaks, passes, lakes, buildings) and, when the text has a house number,
// addresses.
type GeoAdmin struct {
	URL    string // default DefaultSearchURL
	Client *http.Client
}

// Search asks the SearchServer; lang (de, fr, it, en) names the kinds.
func (g *GeoAdmin) Search(ctx context.Context, text, lang string) ([]Found, error) {
	origins := "gazetteer"
	if strings.ContainsAny(text, "0123456789") {
		origins += ",address"
	}
	u := g.URL
	if u == "" {
		u = DefaultSearchURL
	}
	u += "?" + url.Values{
		"type": {"locations"}, "searchText": {text}, "origins": {origins},
		"sr": {"4326"}, "limit": {"15"}, "lang": {lang},
	}.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	client := g.Client
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("places: search: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("places: search: HTTP %d", resp.StatusCode)
	}
	var body struct {
		Results []struct {
			Attrs struct {
				Label, Origin string
				Lon, Lat      float64
			} `json:"attrs"`
		} `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("places: search: %w", err)
	}
	out := []Found{}
	for _, r := range body.Results {
		a := r.Attrs
		f := Found{Kind: "name", At: [2]float64{a.Lon, a.Lat}}
		if a.Origin == "address" {
			f.Kind = "address"
		}
		f.Name, f.Detail = parseLabel(a.Label)
		if f.Name != "" {
			out = append(out, f)
		}
	}
	return out, nil
}

var (
	// "<i>Hauptgipfel</i> <b>Brisen</b> (UR) - Isenthal"; the kind is missing
	// for some names.
	nameLabel = regexp.MustCompile(`^(?:<i>(.*?)</i>\s*)?<b>(.*?)</b>\s*(?:\((.*?)\))?\s*(?:-\s*(.*))?$`)
	// "Seestrasse 1 <b>6375 Beckenried</b>"
	addressLabel = regexp.MustCompile(`^(.+?)\s*<b>(.*?)</b>$`)
	tags         = regexp.MustCompile(`<[^>]*>`)
)

// parseLabel splits a SearchServer label into a name and what it is
// ("Hauptgipfel, Isenthal (UR)").
func parseLabel(label string) (name, detail string) {
	text := func(s string) string {
		return strings.TrimSpace(html.UnescapeString(tags.ReplaceAllString(s, "")))
	}
	if m := nameLabel.FindStringSubmatch(label); m != nil {
		// Alternative names are joined with "|".
		name = strings.ReplaceAll(text(m[2]), "|", " / ")
		var parts []string
		if kind := text(m[1]); kind != "" {
			parts = append(parts, kind)
		}
		if where := text(m[4]); where != "" {
			if canton := text(m[3]); canton != "" {
				where += " (" + canton + ")"
			}
			parts = append(parts, where)
		}
		return name, strings.Join(parts, ", ")
	}
	if m := addressLabel.FindStringSubmatch(label); m != nil {
		return text(m[1]) + ", " + text(m[2]), ""
	}
	return text(label), ""
}
