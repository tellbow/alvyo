// SPDX-License-Identifier: AGPL-3.0-only
//
// Komoot API usage (login, tour list, tour coordinates) follows wanderer's
// Komoot plugin (github.com/open-wanderer/wanderer, plugins/komoot, AGPL-3.0),
// re-implemented for Alvyo with net/http on 2026-09-23.

package imports

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/tellbow/alvyo/swiss/geo"
)

// KomootAPI is Komoot's (unofficial) API.
const KomootAPI = "https://api.komoot.de"

// Komoot errors.
var (
	ErrKomootLogin = errors.New("komoot: e-mail or password wrong")
	ErrKomoot      = errors.New("komoot: request failed")
)

// Komoot talks to the Komoot API on behalf of a user.
type Komoot struct {
	API  string
	HTTP *http.Client
}

// KomootSession is what Komoot returns on login: the user id and an API
// token. The password is not kept.
type KomootSession struct {
	UserID string
	Token  string
}

// KomootTour is a tour in the user's Komoot list.
type KomootTour struct {
	ID        int64   `json:"id"`
	Type      string  `json:"type" doc:"tour_planned or tour_recorded"`
	Name      string  `json:"name"`
	Date      string  `json:"date"`
	Sport     string  `json:"sport"`
	DistanceM float64 `json:"distance"`
}

func (k *Komoot) client() *http.Client {
	if k.HTTP != nil {
		return k.HTTP
	}
	return &http.Client{Timeout: 20 * time.Second}
}

func basic(user, secret string) string {
	return "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+secret))
}

// get fetches a JSON document; auth is the Authorization header value.
func (k *Komoot) get(ctx context.Context, path string, query url.Values, auth string, out any) error {
	u := k.API + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", auth)
	req.Header.Set("Accept", "application/hal+json")
	resp, err := k.client().Do(req)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrKomoot, err)
	}
	defer func() { _ = resp.Body.Close() }()
	switch {
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden:
		return ErrKomootLogin
	case resp.StatusCode != http.StatusOK:
		// Komoot's error bodies are not passed on: they could echo input.
		return fmt.Errorf("%w: HTTP %d", ErrKomoot, resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 16<<20)).Decode(out)
}

// Login exchanges e-mail and password for a session. The password is only
// sent to Komoot, never stored or logged.
func (k *Komoot) Login(ctx context.Context, email, password string) (KomootSession, error) {
	var r struct {
		Username string `json:"username"`
		Password string `json:"password"` // the API token
	}
	if err := k.get(ctx, "/v006/account/email/"+url.PathEscape(email)+"/", nil, basic(email, password), &r); err != nil {
		return KomootSession{}, err
	}
	if r.Username == "" || r.Password == "" {
		return KomootSession{}, fmt.Errorf("%w: unexpected login response", ErrKomoot)
	}
	return KomootSession{UserID: r.Username, Token: r.Password}, nil
}

// Tours lists the user's tours, newest first (page is 0-based).
func (k *Komoot) Tours(ctx context.Context, s KomootSession, page, limit int) (tours []KomootTour, totalPages int, err error) {
	var r struct {
		Embedded struct {
			Tours []KomootTour `json:"tours"`
		} `json:"_embedded"`
		Page struct {
			TotalPages int `json:"totalPages"`
		} `json:"page"`
	}
	q := url.Values{"page": {strconv.Itoa(page)}, "limit": {strconv.Itoa(limit)},
		"sort_field": {"date"}, "sort_direction": {"desc"}}
	if err := k.get(ctx, "/v007/users/"+url.PathEscape(s.UserID)+"/tours/", q, basic(s.UserID, s.Token), &r); err != nil {
		return nil, 0, err
	}
	if r.Embedded.Tours == nil {
		r.Embedded.Tours = []KomootTour{}
	}
	return r.Embedded.Tours, r.Page.TotalPages, nil
}

// Track fetches the line of a tour.
func (k *Komoot) Track(ctx context.Context, s KomootSession, id int64) (Track, error) {
	var r struct {
		Name     string `json:"name"`
		Embedded struct {
			Coordinates struct {
				Items []struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"items"`
			} `json:"coordinates"`
		} `json:"_embedded"`
	}
	q := url.Values{"_embedded": {"coordinates"}, "format": {"coordinate_array"}}
	if err := k.get(ctx, fmt.Sprintf("/v007/tours/%d", id), q, basic(s.UserID, s.Token), &r); err != nil {
		return Track{}, err
	}
	t := Track{Name: r.Name}
	for _, c := range r.Embedded.Coordinates.Items {
		t.Points = append(t.Points, geo.Point{Lon: c.Lng, Lat: c.Lat})
	}
	t = clean(t)
	return t, nil
}
