package ojp

import (
	"errors"
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
	dep := requestXML(Query{From: "8509411", To: "8509965", At: at}, "odysgeh <test>", at)
	if !strings.Contains(dep, "<StopPlaceRef>8509411</StopPlaceRef></PlaceRef><DepArrTime>2026-07-04T06:00:00Z</DepArrTime></Origin>") ||
		!strings.Contains(dep, "odysgeh &lt;test&gt;") || !strings.Contains(dep, "<NumberOfResults>4</NumberOfResults>") {
		t.Errorf("departure request:\n%s", dep)
	}
	arr := requestXML(Query{From: "8509411", To: "8509965", At: at, Arrive: true, Results: 2}, "odysgeh", at)
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
