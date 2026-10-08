// Package telemetry traces the API by OTLP to an OpenTelemetry collector
// (the standard variables: OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME,
// OTEL_RESOURCE_ATTRIBUTES …; nothing without an endpoint, or with
// OTEL_SDK_DISABLED=true) and measures it for Prometheus to scrape. Logs stay
// on stderr, where the collector reads them as it reads every container's,
// with the ids of the trace they belong to.
package telemetry

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"regexp"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/contrib/instrumentation/runtime"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	otelprom "go.opentelemetry.io/otel/exporters/prometheus"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.40.0"
	"go.opentelemetry.io/otel/trace"
)

// Tracing reports whether an OTLP endpoint for traces is configured and the
// SDK not switched off.
func Tracing() bool {
	return os.Getenv("OTEL_SDK_DISABLED") != "true" &&
		(os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "" || os.Getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") != "")
}

// Telemetry holds the providers set up by Start.
type Telemetry struct {
	traces  *sdktrace.TracerProvider // nil without tracing
	metrics *sdkmetric.MeterProvider
	// Metrics is the Prometheus endpoint (/metrics), on a port of its own.
	Metrics http.Handler
}

// Start makes the providers global: request, database and Go runtime
// metrics for Metrics, and with traces also the spans, including outgoing
// requests of the default transport (GraphHopper, geo.admin, MeteoSwiss,
// OJP …). Shutdown sends what is still buffered.
func Start(ctx context.Context, service, version string, traces bool) (*Telemetry, error) {
	// The variables come last: OTEL_SERVICE_NAME wins.
	res, err := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(service), semconv.ServiceVersion(version)),
		resource.WithTelemetrySDK(), resource.WithHost(), resource.WithFromEnv())
	if err != nil {
		return nil, err
	}
	registry := prometheus.NewRegistry()
	exp, err := otelprom.New(otelprom.WithRegisterer(registry))
	if err != nil {
		return nil, err
	}
	t := &Telemetry{
		metrics: sdkmetric.NewMeterProvider(sdkmetric.WithReader(exp), sdkmetric.WithResource(res)),
		Metrics: promhttp.HandlerFor(registry, promhttp.HandlerOpts{}),
	}
	otel.SetMeterProvider(t.metrics)
	if err := runtime.Start(runtime.WithMeterProvider(t.metrics)); err != nil {
		return nil, err
	}
	if traces {
		exp, err := otlptracehttp.New(ctx)
		if err != nil {
			return nil, err
		}
		t.traces = sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(redact{}), sdktrace.WithBatcher(exp), sdktrace.WithResource(res))
		otel.SetTracerProvider(t.traces)
		otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
		http.DefaultTransport = otelhttp.NewTransport(http.DefaultTransport)
	}
	return t, nil
}

// tokenPath matches the tokens in addresses: a live location's link and a
// friend invite let whoever has them in.
var tokenPath = regexp.MustCompile(`/(live/view|friend-invites)/[^/?#]+`)

// redact masks the tokens in the addresses of spans as they start, before
// any exporter sees them.
type redact struct{}

func (redact) OnStart(_ context.Context, s sdktrace.ReadWriteSpan) {
	for _, kv := range s.Attributes() {
		switch kv.Key {
		case semconv.URLPathKey, semconv.URLFullKey, "http.target", "http.url":
			if v := tokenPath.ReplaceAllString(kv.Value.AsString(), "/$1/-"); v != kv.Value.AsString() {
				s.SetAttributes(attribute.String(string(kv.Key), v))
			}
		}
	}
}

func (redact) OnEnd(sdktrace.ReadOnlySpan)      {}
func (redact) Shutdown(context.Context) error   { return nil }
func (redact) ForceFlush(context.Context) error { return nil }

// Shutdown sends what is buffered and stops the providers.
func (t *Telemetry) Shutdown(ctx context.Context) error {
	err := t.metrics.Shutdown(ctx)
	if t.traces != nil {
		err = errors.Join(err, t.traces.Shutdown(ctx))
	}
	return err
}

// WithTraceIDs adds the ids of the current span to records logged with a
// context ("trace_id", "span_id"), so a log line leads to its trace.
func WithTraceIDs(h slog.Handler) slog.Handler { return traceIDs{h} }

type traceIDs struct{ slog.Handler }

func (h traceIDs) Handle(ctx context.Context, r slog.Record) error {
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		r.AddAttrs(slog.String("trace_id", sc.TraceID().String()), slog.String("span_id", sc.SpanID().String()))
	}
	return h.Handler.Handle(ctx, r)
}

func (h traceIDs) WithAttrs(attrs []slog.Attr) slog.Handler {
	return traceIDs{h.Handler.WithAttrs(attrs)}
}

func (h traceIDs) WithGroup(name string) slog.Handler { return traceIDs{h.Handler.WithGroup(name)} }

// Handler traces and measures every request but the health checks. Spans
// carry the path, not the query: the share token of an unlisted item (?t=)
// stays out.
func Handler(next http.Handler) http.Handler {
	return otelhttp.NewHandler(next, "http",
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != "/healthz" && r.URL.Path != "/readyz" }),
		// Named after the operation once it is known (see Route).
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method }))
}

// Route names the request's span and metrics after the operation's path
// pattern ("GET /api/v1/routes/{id}"), not the address with its ids.
func Route(ctx context.Context, method, route string) {
	span := trace.SpanFromContext(ctx)
	span.SetName(method + " " + route)
	span.SetAttributes(semconv.HTTPRoute(route))
	if l, ok := otelhttp.LabelerFromContext(ctx); ok {
		l.Add(semconv.HTTPRoute(route))
	}
}
