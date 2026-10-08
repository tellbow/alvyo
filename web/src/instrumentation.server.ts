import { metrics } from '@opentelemetry/api';
import { PrometheusExporter } from '@opentelemetry/exporter-prometheus';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { detectResources, envDetector, resourceFromAttributes } from '@opentelemetry/resources';
import { MeterProvider } from '@opentelemetry/sdk-metrics';
import {
	BatchSpanProcessor,
	NodeTracerProvider,
	type Span,
	type SpanProcessor
} from '@opentelemetry/sdk-trace-node';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

// Traces (SvelteKit's own spans: requests, hooks, loads, actions) by OTLP
// to the collector, as the API sends them, when an endpoint is set
// (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME …); metrics for Prometheus
// to scrape on a port of their own (METRICS_PORT, e.g. 9464). Loaded before
// the app.
const env = process.env;
const on = env.OTEL_SDK_DISABLED !== 'true';
const tracing = on && !!(env.OTEL_EXPORTER_OTLP_ENDPOINT || env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT);
const metricsPort = Number(env.METRICS_PORT) || 0;

// The variables win (OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES).
const resource = resourceFromAttributes({ [ATTR_SERVICE_NAME]: 'alvyo-web' }).merge(
	detectResources({ detectors: [envDetector] })
);
const stops: (() => Promise<void>)[] = [];

/** SvelteKit's spans carry the whole address: without its query (share
 * and reset tokens) and with the tokens of live locations and invites
 * masked, as in analyticsUrl. */
const redact: SpanProcessor = {
	onStart(span: Span) {
		const url = span.attributes['http.url'];
		if (typeof url !== 'string') return;
		const u = new URL(url);
		span.setAttribute(
			'http.url',
			u.origin + u.pathname.replace(/\/(live|friends\/invite)\/[^/]+/, '/$1/-')
		);
	},
	onEnd() {},
	forceFlush: () => Promise.resolve(),
	shutdown: () => Promise.resolve()
};

if (tracing) {
	const traces = new NodeTracerProvider({
		resource,
		spanProcessors: [redact, new BatchSpanProcessor(new OTLPTraceExporter())]
	});
	// Global, with the async context and W3C trace headers.
	traces.register();
	stops.push(() => traces.shutdown());
}
if (on && metricsPort) {
	const meters = new MeterProvider({
		resource,
		readers: [new PrometheusExporter({ port: metricsPort })]
	});
	metrics.setGlobalMeterProvider(meters);
	stops.push(() => meters.shutdown());
}
// adapter-node's graceful shutdown: send what is still buffered.
process.on('sveltekit:shutdown', () => {
	void Promise.all(stops.map((stop) => stop()));
});
