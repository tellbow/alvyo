//go:build live

package spam

import (
	"context"
	"testing"
)

func TestMailboxLive(t *testing.T) {
	ctx := context.Background()
	if !MailboxPlausible(ctx, "a@gmail.com") {
		t.Error("gmail.com takes mail")
	}
	if MailboxPlausible(ctx, "a@example.com") {
		t.Error("example.com has a null MX")
	}
	if MailboxPlausible(ctx, "a@nothing-here.invalid") {
		t.Error(".invalid does not exist")
	}
}
