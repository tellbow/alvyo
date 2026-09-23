package imports

import (
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeKomoot mimics the three Komoot endpoints the importer uses.
func fakeKomoot(t *testing.T) *httptest.Server {
	t.Helper()
	auth := func(r *http.Request, user, secret string) bool {
		return r.Header.Get("Authorization") == "Basic "+base64.StdEncoding.EncodeToString([]byte(user+":"+secret))
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v006/account/email/{email}/", func(w http.ResponseWriter, r *http.Request) {
		if !auth(r, r.PathValue("email"), "right") {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"wrong password for ` + r.PathValue("email") + `"}`))
			return
		}
		_, _ = w.Write([]byte(`{"username":"123456","password":"api-token","locale":"de_CH"}`))
	})
	mux.HandleFunc("GET /v007/users/123456/tours/", func(w http.ResponseWriter, r *http.Request) {
		if !auth(r, "123456", "api-token") || r.URL.Query().Get("sort_direction") != "desc" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`{"_embedded":{"tours":[
			{"id":111,"type":"tour_recorded","name":"Faulhorn","date":"2026-08-01T07:00:00.000Z","sport":"hike","distance":10500.5},
			{"id":222,"type":"tour_planned","name":"Lago di Como","date":"2026-07-01T07:00:00.000Z","sport":"hike","distance":8000}
		]},"page":{"totalPages":1}}`))
	})
	mux.HandleFunc("GET /v007/tours/111", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("_embedded") != "coordinates" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{"name":"Faulhorn","_embedded":{"coordinates":{"items":[
			{"lat":46.665,"lng":8.04,"alt":2200,"t":0},{"lat":46.665,"lng":8.041,"alt":2201,"t":1000},
			{"lat":46.665,"lng":8.041,"alt":2201,"t":2000},{"lat":46.666,"lng":8.042,"alt":2210,"t":3000}]}}}`))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestKomoot(t *testing.T) {
	ctx := context.Background()
	k := &Komoot{API: fakeKomoot(t).URL}
	if _, err := k.Login(ctx, "hiker@example.ch", "wrong"); !errors.Is(err, ErrKomootLogin) {
		t.Fatalf("wrong password: %v", err)
	} else if strings.Contains(err.Error(), "hiker@") {
		t.Errorf("Komoot's error body leaked into the error: %v", err)
	}
	s, err := k.Login(ctx, "hiker@example.ch", "right")
	if err != nil || s.UserID != "123456" || s.Token != "api-token" {
		t.Fatalf("login: %+v %v", s, err)
	}
	tours, pages, err := k.Tours(ctx, s, 0, 50)
	if err != nil || pages != 1 || len(tours) != 2 || tours[0].ID != 111 || tours[0].Type != "tour_recorded" || tours[0].DistanceM != 10500.5 {
		t.Fatalf("tours: %+v %d %v", tours, pages, err)
	}
	tr, err := k.Track(ctx, s, 111)
	if err != nil || tr.Name != "Faulhorn" || len(tr.Points) != 3 || tr.Points[2].Lat != 46.666 {
		t.Fatalf("track: %+v %v", tr, err)
	}
	if _, err := k.Track(ctx, KomootSession{UserID: "123456", Token: "expired"}, 222); !errors.Is(err, ErrKomoot) && !errors.Is(err, ErrKomootLogin) {
		t.Errorf("missing tour: %v", err)
	}
}
