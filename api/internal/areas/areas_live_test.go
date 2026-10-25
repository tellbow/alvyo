//go:build live

package areas

import (
	"context"
	"testing"

	"github.com/tellbow/alvyo/api/internal/testdb"
	"github.com/tellbow/alvyo/swiss/geo"
)

// TestCrossedLive walks the line of the end-to-end test areas.e2e.ts, whose
// fake geo.admin answers with what geo.admin answered on 2026-10-25
// (web/tests/e2e/files/identify-grindelwald.json): when this fails, record
// it again.
// Run with: go test -tags live ./internal/areas/
func TestCrossedLive(t *testing.T) {
	f := &Finder{DB: testdb.New(t), UserAgent: "alvyo-test"}
	got, err := f.Crossed(context.Background(), []geo.Point{{Lon: 8.01, Lat: 46.665}, {Lon: 8.04, Lat: 46.665}})
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range got {
		if a.Kind == "wildlife_rest" && a.Name == "Grindelwald Spilmatten-Reetihorn (Nr. 1.00)" {
			if !a.Binding || a.Period == nil || *a.Period != (Period{From: "12-01", To: "04-20"}) {
				t.Errorf("rules changed: %+v", a)
			}
			return
		}
	}
	t.Errorf("Spilmatten-Reetihorn not among %+v", got)
}
