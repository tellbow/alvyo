package mailer

import (
	"context"
	"testing"
	"time"

	"github.com/tellbow/alvyo/api/internal/ratelimit"
)

func TestPerRecipient(t *testing.T) {
	rec := &Recorder{}
	p := PerRecipient{Next: rec, Limit: ratelimit.New(time.Hour, 2)}
	ctx := context.Background()
	for _, to := range []string{"a@example.ch", "A@example.ch", "a@example.ch", "b@example.ch"} {
		if err := p.Send(ctx, Message{To: to}); err != nil {
			t.Fatal(err)
		}
	}
	if sent := rec.Sent(); len(sent) != 3 || sent[2].To != "b@example.ch" {
		t.Errorf("sent %v: two to a, the third dropped, one to b", sent)
	}
}
