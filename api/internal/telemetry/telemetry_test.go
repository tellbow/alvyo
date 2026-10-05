package telemetry

import (
	"bytes"
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

// An unlisted item's share token reaches the handler but not the span; the
// span is named after the operation; health checks make none.
func TestHandler(t *testing.T) {
	spans := tracetest.NewSpanRecorder()
	prev := otel.GetTracerProvider()
	otel.SetTracerProvider(sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(spans)))
	t.Cleanup(func() { otel.SetTracerProvider(prev) })

	var token string
	h := Handler(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		token = r.URL.Query().Get("t")
		Route(r.Context(), r.Method, "/api/v1/routes/{id}")
	}))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/routes/42?t=geheim&x=1", nil))
	if token != "geheim" {
		t.Errorf("handler got token %q", token)
	}
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/healthz", nil))

	ended := spans.Ended()
	if len(ended) != 1 {
		t.Fatalf("%d spans, want 1 (no health check)", len(ended))
	}
	if name := ended[0].Name(); name != "GET /api/v1/routes/{id}" {
		t.Errorf("span name %q", name)
	}
	for _, a := range ended[0].Attributes() {
		if strings.Contains(a.Value.String(), "geheim") {
			t.Errorf("token in span attribute %s=%s", a.Key, a.Value.String())
		}
	}
}

// A line logged during a request carries its trace's ids; one without
// none.
func TestWithTraceIDs(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(WithTraceIDs(slog.NewTextHandler(&buf, nil))).With("svc", "api")
	tp := sdktrace.NewTracerProvider()
	ctx, span := tp.Tracer("test").Start(context.Background(), "request")
	log.InfoContext(ctx, "inside")
	span.End()
	log.Info("outside")
	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	want := "trace_id=" + span.SpanContext().TraceID().String()
	if len(lines) != 2 || !strings.Contains(lines[0], want) || !strings.Contains(lines[0], "svc=api") || strings.Contains(lines[1], "trace_id") {
		t.Errorf("logged %q", lines)
	}
}

// Requests are measured per operation for Prometheus.
func TestMetrics(t *testing.T) {
	tel, err := Start(context.Background(), "alvyo-api", "test", false)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = tel.Shutdown(context.Background()) })
	h := Handler(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		Route(r.Context(), r.Method, "/api/v1/routes/{id}")
	}))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/routes/42", nil))

	rec := httptest.NewRecorder()
	tel.Metrics.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	body := rec.Body.String()
	for _, want := range []string{`http_server_request_duration_seconds_count{`, `http_route="/api/v1/routes/{id}"`, `go_goroutine_count`} {
		if !strings.Contains(body, want) {
			t.Errorf("no %s in /metrics", want)
		}
	}
}
