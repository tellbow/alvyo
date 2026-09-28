//go:build live

package ojp

import (
	"context"
	"os"
	"testing"
	"time"
)

// Run with ALVYO_OJP_TOKEN set: go test -tags live ./ojp/
func TestLiveSargansWeisstannen(t *testing.T) {
	token := os.Getenv("ALVYO_OJP_TOKEN")
	if token == "" {
		t.Skip("ALVYO_OJP_TOKEN not set")
	}
	c := &Client{URL: DefaultURL, Token: token, RequestorRef: "alvyo-live-test"}
	zurich, _ := time.LoadLocation("Europe/Zurich")
	next := time.Now().In(zurich).Add(24 * time.Hour)
	at := time.Date(next.Year(), next.Month(), next.Day(), 8, 0, 0, 0, zurich)
	trips, err := c.Trips(context.Background(), Query{From: Stop("8509411"), To: Stop("8509965"), At: at})
	if err != nil {
		t.Fatal(err)
	}
	if len(trips) == 0 {
		t.Fatal("no trips")
	}
	for _, tr := range trips {
		t.Logf("%s → %s, %d transfers", tr.Start.In(zurich).Format("15:04"), tr.End.In(zurich).Format("15:04"), tr.Transfers)
		for _, l := range tr.Legs {
			t.Logf("  %s %s %s %s→%s %s–%s", l.Kind, l.Mode, l.Line, l.From, l.To,
				l.Departure.In(zurich).Format("15:04"), l.Arrival.In(zurich).Format("15:04"))
		}
		if tr.Start.Before(at.Add(-time.Minute)) || len(tr.Legs) == 0 {
			t.Errorf("trip %+v", tr)
		}
	}
}
