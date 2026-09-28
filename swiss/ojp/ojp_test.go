package ojp

import (
	"context"
	"errors"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestParseTrips(t *testing.T) {
	f, err := os.Open("testdata/zurich-weisstannen.xml") // recorded response, Zürich HB → Weisstannen
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	trips, err := Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	if len(trips) != 2 {
		t.Fatalf("%d trips", len(trips))
	}
	tr := trips[0]
	if tr.Transfers != 1 || len(tr.Legs) != 3 || !tr.End.After(tr.Start) || tr.Duration <= 0 {
		t.Fatalf("trip %+v", tr)
	}
	train, walk, bus := tr.Legs[0], tr.Legs[1], tr.Legs[2]
	if train.Kind != "ride" || train.Mode != "rail" || !strings.HasPrefix(train.Line, "IC") ||
		train.From != "Zürich HB" || train.To != "Sargans" || train.Direction != "Chur" || train.Platform == "" {
		t.Errorf("train %+v", train)
	}
	if walk.Kind != "walk" || walk.To != "Sargans, Bahnhof" || walk.DurationMin != 3 || !walk.Departure.IsZero() {
		t.Errorf("walk %+v", walk)
	}
	if bus.Mode != "bus" || bus.Line != "B 432" || bus.To != "Weisstannen, Oberdorf" || bus.Departure.Before(train.Arrival) {
		t.Errorf("bus %+v", bus)
	}
}

func TestParseEstimates(t *testing.T) {
	// A real-time element without a time costs the delay, not the answer.
	body, err := os.ReadFile("testdata/zurich-weisstannen.xml")
	if err != nil {
		t.Fatal(err)
	}
	xml := strings.Replace(string(body), "<TimetabledTime>2026-09-23T06:07:00Z</TimetabledTime>",
		"<TimetabledTime>2026-09-23T06:07:00Z</TimetabledTime><EstimatedTime/>", 1)
	xml = strings.Replace(xml, "<TimetabledTime>2026-09-23T07:07:00Z</TimetabledTime>",
		"<TimetabledTime>2026-09-23T07:07:00Z</TimetabledTime><EstimatedTime>2026-09-23T07:09:30Z</EstimatedTime>", 1)
	trips, err := Parse(strings.NewReader(xml))
	if err != nil || len(trips) != 2 {
		t.Fatalf("%d trips, %v", len(trips), err)
	}
	if first := trips[0].Legs[0]; first.DelayMin != 0 || first.Departure.IsZero() {
		t.Errorf("train without estimate %+v", first)
	}
	if late := trips[1].Legs[0]; late.DelayMin != 2 {
		t.Errorf("train 2½ min late: delay %d", late.DelayMin)
	}
}

func TestParseNoTrip(t *testing.T) {
	f, err := os.Open("testdata/no-trip.xml")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	trips, err := Parse(f)
	if err != nil || len(trips) != 0 {
		t.Errorf("no trip: %v, %v", trips, err)
	}
	_, err = Parse(strings.NewReader(`<OJP><OJPResponse><ServiceDelivery><OJPTripDelivery><ErrorCondition>` +
		`<TripProblemType>TRIP_ORIGIN_UNKNOWN</TripProblemType></ErrorCondition></OJPTripDelivery></ServiceDelivery></OJPResponse></OJP>`))
	if !errors.Is(err, ErrUnavailable) {
		t.Errorf("other problem: %v", err)
	}
}

func TestRequestXML(t *testing.T) {
	at := time.Date(2026, 7, 4, 8, 0, 0, 0, time.FixedZone("CEST", 2*3600))
	dep := requestXML(Query{From: Stop("8509411"), To: Stop("8509965"), At: at}, "alvyo <test>", at)
	if !strings.Contains(dep, "<StopPlaceRef>8509411</StopPlaceRef></PlaceRef><DepArrTime>2026-07-04T06:00:00Z</DepArrTime></Origin>") ||
		!strings.Contains(dep, "alvyo &lt;test&gt;") || !strings.Contains(dep, "<NumberOfResults>4</NumberOfResults>") {
		t.Errorf("departure request:\n%s", dep)
	}
	arr := requestXML(Query{From: Stop("8509411"), To: Stop("8509965"), At: at, Arrive: true, Results: 2}, "alvyo", at)
	if !strings.Contains(arr, "<StopPlaceRef>8509965</StopPlaceRef></PlaceRef><DepArrTime>2026-07-04T06:00:00Z</DepArrTime></Destination>") {
		t.Errorf("arrival request:\n%s", arr)
	}
}

func TestParseDuration(t *testing.T) {
	for in, want := range map[string]time.Duration{
		"PT57M": 57 * time.Minute, "PT1H5M": 65 * time.Minute, "P1DT2H": 26 * time.Hour, "PT30S": 30 * time.Second,
	} {
		if got, err := parseDuration(in); err != nil || got != want {
			t.Errorf("%s: %v %v", in, got, err)
		}
	}
	if _, err := parseDuration("57 min"); err == nil {
		t.Error("invalid duration accepted")
	}
}

func TestTrips(t *testing.T) {
	answer, err := os.ReadFile("testdata/zurich-weisstannen.xml")
	if err != nil {
		t.Fatal(err)
	}
	status := http.StatusOK
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if r.Method != http.MethodPost || r.Header.Get("Authorization") != "Bearer key" ||
			!strings.HasPrefix(r.Header.Get("Content-Type"), "application/xml") ||
			!strings.Contains(string(body), "8503000") || !strings.Contains(string(body), "<siri:RequestorRef>alvyo</siri:RequestorRef>") {
			t.Errorf("request %s %v: %s", r.Method, r.Header, body)
		}
		w.WriteHeader(status)
		_, _ = w.Write(answer)
	}))
	defer srv.Close()
	c := &Client{URL: srv.URL, Token: "key", RequestorRef: "alvyo"}
	q := Query{From: Stop("8503000"), To: Stop("8509434"), At: time.Date(2026, 9, 26, 7, 0, 0, 0, time.UTC)}

	trips, err := c.Trips(context.Background(), q)
	if err != nil || len(trips) != 2 {
		t.Fatalf("trips: %d, %v", len(trips), err)
	}
	status = http.StatusTooManyRequests // over the quota
	if _, err := c.Trips(context.Background(), q); !errors.Is(err, ErrUnavailable) {
		t.Errorf("err = %v, want ErrUnavailable", err)
	}
}

// From a home in Thun to Spiez: the walk from the door and the rides with
// their ways.
func TestParseFromAPosition(t *testing.T) {
	f, err := os.Open("testdata/home-spiez.xml") // recorded response, a position in Thun → Spiez
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	trips, err := Parse(f)
	if err != nil || len(trips) != 1 {
		t.Fatalf("%d trips, %v", len(trips), err)
	}
	legs := trips[0].Legs
	first := legs[0]
	// The track starts on the nearest path, a few metres from the position.
	near := func(p [2]float64) bool { return math.Abs(p[0]-7.6197) < 0.0006 && math.Abs(p[1]-46.764) < 0.0004 }
	if first.Kind != "walk" || first.From != "Home" || len(first.Track) < 2 || !near(first.Track[0]) {
		t.Fatalf("first leg %+v", first)
	}
	rides := 0
	for _, l := range legs {
		if l.Kind == "ride" {
			rides++
			if len(l.Track) < 2 {
				t.Errorf("ride without its way: %+v", l)
			}
		}
	}
	if rides == 0 || legs[len(legs)-1].To != "Spiez" && legs[len(legs)-1].Kind == "ride" {
		t.Errorf("legs %+v", legs)
	}
}

func TestRequestFromAPositionWithLines(t *testing.T) {
	at := time.Date(2026, 7, 4, 6, 0, 0, 0, time.UTC)
	q := Query{From: Place{Lon: 7.6197, Lat: 46.764, Name: "Zuhause <Thun>"}, To: Stop("8507483"), At: at, Lines: true}
	x := requestXML(q, "alvyo", at)
	for _, want := range []string{
		"<Origin><PlaceRef><GeoPosition><siri:Longitude>7.619700</siri:Longitude><siri:Latitude>46.764000</siri:Latitude></GeoPosition><Name><Text>Zuhause &lt;Thun&gt;</Text></Name></PlaceRef><DepArrTime>",
		"<IncludeLegProjection>true</IncludeLegProjection>",
	} {
		if !strings.Contains(x, want) {
			t.Errorf("missing %s in\n%s", want, x)
		}
	}
	if strings.Contains(requestXML(Query{From: Stop("8509411"), To: Stop("8509965"), At: at}, "alvyo", at), "IncludeLegProjection") {
		t.Error("ways asked for without Lines")
	}
}
