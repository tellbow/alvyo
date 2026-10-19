package elevation

import (
	"context"
	"errors"
	"math"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"testing"
	"testing/synctest"
	"time"
)

// What the fake geo.admin does with one request.
type answer int

const (
	answerOK         answer = iota
	answerBusy              // 503
	answerTooMany           // 429
	answerBadRequest        // 400: our mistake, not worth a retry
	answerBroken            // 200 with a cut-off body
	answerNoNetwork         // the connection fails
	answerSlow              // no answer before the client's timeout
	answers
)

// faultTransport plays geo.admin without a network, so that it runs inside
// a synctest bubble: the answers come from a seed, waits are on the fake
// clock, and every call is recorded with its time.
type faultTransport struct {
	plan    []answer
	calls   []time.Time
	profile http.HandlerFunc
}

func (f *faultTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	f.calls = append(f.calls, time.Now())
	a := answerOK
	if n := len(f.calls) - 1; n < len(f.plan) {
		a = f.plan[n]
	}
	rec := httptest.NewRecorder()
	switch a {
	case answerOK:
		f.profile(rec, req)
	case answerBusy:
		rec.WriteHeader(http.StatusServiceUnavailable)
	case answerTooMany:
		rec.WriteHeader(http.StatusTooManyRequests)
	case answerBadRequest:
		rec.WriteHeader(http.StatusBadRequest)
	case answerBroken:
		_, _ = rec.WriteString(`[{"dist": 0, "alts": {"COMB": 10`)
	case answerNoNetwork:
		return nil, errors.New("connection refused")
	case answerSlow:
		select {
		case <-req.Context().Done(): // the client gave up
			return nil, req.Context().Err()
		case <-time.After(time.Hour):
		}
		f.profile(rec, req)
	}
	res := rec.Result()
	res.Request = req
	return res, nil
}

// TestSampleUnderFaults runs Sample against many random sequences of
// failures, with the real waits (1 s, 2 s plus jitter) and the real 20 s
// timeout on the fake clock. Each seed must end as the retry rules say: at
// most three tries, none after a 400, the waits kept, and done in time.
func TestSampleUnderFaults(t *testing.T) {
	for seed := range uint64(300) {
		rng := rand.New(rand.NewPCG(seed, 0))
		plan := make([]answer, 3)
		for i := range plan {
			plan[i] = answer(rng.IntN(int(answers)))
		}
		synctest.Test(t, func(t *testing.T) {
			ft := &faultTransport{plan: plan, profile: fakeProfile(t, slope)}
			g := &GeoAdmin{Client: &http.Client{Transport: ft, Timeout: 20 * time.Second}}
			start := time.Now()
			h, err := g.Sample(context.Background(), line(3))
			took := time.Since(start)

			// What the rules say should happen.
			wantCalls, wantOK := 0, false
			for _, a := range plan {
				wantCalls++
				if a == answerOK {
					wantOK = true
				}
				if a == answerOK || a == answerBadRequest {
					break
				}
			}
			if (err == nil) != wantOK || len(ft.calls) != wantCalls {
				t.Fatalf("seed %d, plan %v: %d calls, err %v; want %d calls, ok %v", seed, plan, len(ft.calls), err, wantCalls, wantOK)
			}
			if err == nil && (len(h) != 3 || math.Abs(h[0]-expected(line(3)[0])) > 0.01) {
				t.Fatalf("seed %d: heights %v", seed, h)
			}
			for i := 1; i < len(ft.calls); i++ {
				gap := ft.calls[i].Sub(ft.calls[i-1])
				if plan[i-1] == answerSlow {
					gap -= 20 * time.Second
				}
				if from := time.Second << (i - 1); gap < from || gap >= from+time.Second {
					t.Fatalf("seed %d: try %d after %v, want %v plus less than 1 s", seed, i+1, gap, from)
				}
			}
			// Three slow tries and both waits: the most a profile may take.
			if took > 3*20*time.Second+(1+2+2)*time.Second {
				t.Fatalf("seed %d: took %v", seed, took)
			}
		})
	}
}

// TestSampleCancelledWhileWaiting: a request that is given up stops the
// retries at once, not after the wait.
func TestSampleCancelledWhileWaiting(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		ft := &faultTransport{plan: []answer{answerBusy, answerBusy, answerBusy}, profile: fakeProfile(t, slope)}
		g := &GeoAdmin{Client: &http.Client{Transport: ft}}
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()
		start := time.Now()
		_, err := g.Sample(ctx, line(3))
		if !errors.Is(err, context.DeadlineExceeded) || len(ft.calls) != 1 || time.Since(start) != 500*time.Millisecond {
			t.Errorf("err %v after %d calls and %v", err, len(ft.calls), time.Since(start))
		}
	})
}
