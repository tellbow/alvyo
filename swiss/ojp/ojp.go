// Package ojp asks the Swiss Open Journey Planner (OJP 2.0,
// opentransportdata.swiss) for public transport connections between stops
// or positions (an address: the planner adds the walk to the stop).
package ojp

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// DefaultURL is the production OJP 2.0 endpoint.
const DefaultURL = "https://api.opentransportdata.swiss/ojp20"

// ErrUnavailable is returned when the planner answers with an error status.
var ErrUnavailable = errors.New("ojp: journey planner unavailable")

// Client calls OJP. Token is the opentransportdata.swiss API key.
type Client struct {
	URL          string
	Token        string
	RequestorRef string // identifies us to the operator, e.g. "alvyo"
	HTTP         *http.Client
}

// Query asks for trips between two places.
type Query struct {
	From, To Place
	At       time.Time // departure, or arrival when Arrive
	Arrive   bool
	Results  int // default 4
	// Lines asks for the way of each leg (Leg.Track).
	Lines bool
}

// Place is a stop (Ref, a Didok number such as 8509411) or, without Ref, a
// position with a name for the answer's legs.
type Place struct {
	Ref      string
	Lon, Lat float64
	Name     string
}

// Stop is the place of a stop.
func Stop(ref string) Place { return Place{Ref: ref} }

// Trip is one connection.
type Trip struct {
	Start     time.Time     `json:"start"`
	End       time.Time     `json:"end"`
	Duration  time.Duration `json:"-"`
	Transfers int           `json:"transfers"`
	Legs      []Leg         `json:"legs"`
}

// Leg is a ride or a walk within a trip.
type Leg struct {
	Kind string `json:"kind" enum:"ride,walk"`
	// Rides: mode (rail, bus, tram, cableway, water …), line ("IR 35",
	// "S1", "81") and direction.
	Mode      string `json:"mode,omitempty"`
	Line      string `json:"line,omitempty"`
	Direction string `json:"direction,omitempty"`
	From      string `json:"from"`
	To        string `json:"to"`
	// Rides only: walks between stops carry just a duration.
	Departure time.Time `json:"departure,omitzero"`
	Arrival   time.Time `json:"arrival,omitzero"`
	// Delay in minutes at departure from real-time data; 0 if on time or unknown.
	DelayMin    int    `json:"delay_min,omitempty"`
	Platform    string `json:"platform,omitempty"`
	DurationMin int    `json:"duration_min,omitempty" doc:"Walks only"`
	// The way, when asked for (Query.Lines): lon, lat per point.
	Track [][2]float64 `json:"track,omitempty"`
}

// Trips asks the planner for connections.
func (c *Client) Trips(ctx context.Context, q Query) ([]Trip, error) {
	body := requestXML(q, c.RequestorRef, time.Now())
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.URL, strings.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/xml; charset=utf-8")
	req.Header.Set("Authorization", "Bearer "+c.Token)
	hc := c.HTTP
	if hc == nil {
		hc = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ojp: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
		return nil, fmt.Errorf("%w: HTTP %d", ErrUnavailable, resp.StatusCode)
	}
	return Parse(io.LimitReader(resp.Body, 8<<20))
}

// placeXML is a PlaceRef. Stop refs are digits (checked by the caller);
// names are escaped.
func placeXML(p Place) string {
	if p.Ref != "" {
		return `<PlaceRef><StopPlaceRef>` + p.Ref + `</StopPlaceRef></PlaceRef>`
	}
	var name bytes.Buffer
	_ = xml.EscapeText(&name, []byte(p.Name))
	return fmt.Sprintf(`<PlaceRef><GeoPosition><siri:Longitude>%.6f</siri:Longitude><siri:Latitude>%.6f</siri:Latitude></GeoPosition><Name><Text>%s</Text></Name></PlaceRef>`,
		p.Lon, p.Lat, name.String())
}

// requestXML builds an OJPTripRequest.
func requestXML(q Query, requestor string, now time.Time) string {
	results := q.Results
	if results <= 0 {
		results = 4
	}
	at := q.At.UTC().Format(time.RFC3339)
	originTime, destTime := "<DepArrTime>"+at+"</DepArrTime>", ""
	if q.Arrive {
		originTime, destTime = "", "<DepArrTime>"+at+"</DepArrTime>"
	}
	lines := ""
	if q.Lines {
		lines = "\n\t\t\t\t\t<IncludeLegProjection>true</IncludeLegProjection>"
	}
	var b bytes.Buffer
	_ = xml.EscapeText(&b, []byte(requestor))
	ts := now.UTC().Format(time.RFC3339)
	return `<?xml version="1.0" encoding="UTF-8"?>
<OJP xmlns="http://www.vdv.de/ojp" xmlns:siri="http://www.siri.org.uk/siri" version="2.0">
	<OJPRequest>
		<siri:ServiceRequest>
			<siri:RequestTimestamp>` + ts + `</siri:RequestTimestamp>
			<siri:RequestorRef>` + b.String() + `</siri:RequestorRef>
			<OJPTripRequest>
				<siri:RequestTimestamp>` + ts + `</siri:RequestTimestamp>
				<Origin>` + placeXML(q.From) + originTime + `</Origin>
				<Destination>` + placeXML(q.To) + destTime + `</Destination>
				<Params>
					<NumberOfResults>` + fmt.Sprint(results) + `</NumberOfResults>` + lines + `
					<UseRealtimeData>explanatory</UseRealtimeData>
				</Params>
			</OJPTripRequest>
		</siri:ServiceRequest>
	</OJPRequest>
</OJP>`
}

// XML shape of the parts of an OJPTripDelivery we read. Tags without a
// namespace match elements of any namespace.
type text struct {
	Text string `xml:"Text"`
}

type callTime struct {
	Timetabled time.Time `xml:"TimetabledTime"`
	// Real-time, when known; text, so that an empty element does not fail
	// the whole answer.
	Estimated string `xml:"EstimatedTime"`
}

type xmlLeg struct {
	Timed *struct {
		Board struct {
			Name      text     `xml:"StopPointName"`
			Quay      text     `xml:"EstimatedQuay"`
			Planned   text     `xml:"PlannedQuay"`
			Departure callTime `xml:"ServiceDeparture"`
		} `xml:"LegBoard"`
		Alight struct {
			Name    text     `xml:"StopPointName"`
			Arrival callTime `xml:"ServiceArrival"`
		} `xml:"LegAlight"`
		Service struct {
			Mode struct {
				PtMode    string `xml:"PtMode"`
				ShortName text   `xml:"ShortName"`
			} `xml:"Mode"`
			Published   text `xml:"PublishedServiceName"`
			Destination text `xml:"DestinationText"`
		} `xml:"Service"`
		Track []position `xml:"LegTrack>TrackSection>LinkProjection>Position"`
	} `xml:"TimedLeg"`
	Transfer *walkXML `xml:"TransferLeg"`
	// ContinuousLeg: walking to or from a stop outside the network.
	Continuous *walkXML `xml:"ContinuousLeg"`
}

type walkXML struct {
	Start    text   `xml:"LegStart>Name"`
	End      text   `xml:"LegEnd>Name"`
	Duration string `xml:"Duration"`
	// Walks from and to a position have a track; walks between stops, if
	// any, a path guidance.
	Track    []position `xml:"LegTrack>TrackSection>LinkProjection>Position"`
	Guidance []position `xml:"PathGuidance>PathGuidanceSection>TrackSection>LinkProjection>Position"`
}

type position struct {
	Lon float64 `xml:"Longitude"`
	Lat float64 `xml:"Latitude"`
}

func track(ps []position) [][2]float64 {
	if len(ps) == 0 {
		return nil
	}
	out := make([][2]float64, len(ps))
	for i, p := range ps {
		out[i] = [2]float64{p.Lon, p.Lat}
	}
	return out
}

type delivery struct {
	Status  string `xml:"OJPResponse>ServiceDelivery>Status"`
	Results []struct {
		Trip struct {
			Start     time.Time `xml:"StartTime"`
			End       time.Time `xml:"EndTime"`
			Duration  string    `xml:"Duration"`
			Transfers int       `xml:"Transfers"`
			Legs      []xmlLeg  `xml:"Leg"`
		} `xml:"Trip"`
	} `xml:"OJPResponse>ServiceDelivery>OJPTripDelivery>TripResult"`
	// e.g. TRIP_NOTRIPFOUND
	Problem string `xml:"OJPResponse>ServiceDelivery>OJPTripDelivery>ErrorCondition>TripProblemType"`
}

// Parse reads an OJP trip response.
func Parse(r io.Reader) ([]Trip, error) {
	var d delivery
	if err := xml.NewDecoder(r).Decode(&d); err != nil {
		return nil, fmt.Errorf("ojp: parse: %w", err)
	}
	switch {
	case d.Problem == "TRIP_NOTRIPFOUND":
		return []Trip{}, nil
	case d.Status == "false" || (d.Problem != "" && len(d.Results) == 0):
		return nil, fmt.Errorf("%w: %s", ErrUnavailable, d.Problem)
	}
	trips := []Trip{}
	for _, res := range d.Results {
		t := res.Trip
		dur, _ := parseDuration(t.Duration)
		trip := Trip{Start: t.Start, End: t.End, Duration: dur, Transfers: t.Transfers, Legs: []Leg{}}
		for _, l := range t.Legs {
			switch {
			case l.Timed != nil:
				tl := l.Timed
				line := strings.TrimSpace(tl.Service.Published.Text)
				if short := tl.Service.Mode.ShortName.Text; short != "" && !strings.HasPrefix(line, short) {
					line = strings.TrimSpace(short + " " + line)
				}
				platform := tl.Board.Quay.Text
				if platform == "" {
					platform = tl.Board.Planned.Text
				}
				leg := Leg{
					Kind: "ride", Mode: tl.Service.Mode.PtMode, Line: line, Direction: tl.Service.Destination.Text,
					From: tl.Board.Name.Text, To: tl.Alight.Name.Text,
					Departure: tl.Board.Departure.Timetabled, Arrival: tl.Alight.Arrival.Timetabled,
					Platform: platform, Track: track(tl.Track),
				}
				if e, err := time.Parse(time.RFC3339, strings.TrimSpace(tl.Board.Departure.Estimated)); err == nil {
					leg.DelayMin = int(e.Sub(leg.Departure).Minutes())
				}
				trip.Legs = append(trip.Legs, leg)
			case l.Transfer != nil || l.Continuous != nil:
				w := l.Transfer
				if w == nil {
					w = l.Continuous
				}
				d, _ := parseDuration(w.Duration)
				walk := Leg{Kind: "walk", From: w.Start.Text, To: w.End.Text,
					DurationMin: int(d.Round(time.Minute).Minutes()), Track: track(w.Track)}
				if walk.Track == nil {
					walk.Track = track(w.Guidance)
				}
				trip.Legs = append(trip.Legs, walk)
			}
		}
		trips = append(trips, trip)
	}
	return trips, nil
}

// parseDuration reads the ISO 8601 durations OJP uses (PT1H23M, P1DT2H).
func parseDuration(s string) (time.Duration, error) {
	if !strings.HasPrefix(s, "P") {
		return 0, fmt.Errorf("ojp: duration %q", s)
	}
	var d time.Duration
	num, inTime := 0, false
	for _, r := range s[1:] {
		switch {
		case r >= '0' && r <= '9':
			num = num*10 + int(r-'0')
		case r == 'T':
			inTime = true
		case r == 'D' && !inTime:
			d += time.Duration(num) * 24 * time.Hour
			num = 0
		case r == 'H' && inTime:
			d += time.Duration(num) * time.Hour
			num = 0
		case r == 'M' && inTime:
			d += time.Duration(num) * time.Minute
			num = 0
		case r == 'S' && inTime:
			d += time.Duration(num) * time.Second
			num = 0
		default:
			return 0, fmt.Errorf("ojp: duration %q", s)
		}
	}
	return d, nil
}
