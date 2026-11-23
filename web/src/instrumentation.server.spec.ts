import { context, propagation, trace, type ProxyTracerProvider } from '@opentelemetry/api';
import type { TracerProvider } from '@opentelemetry/sdk-trace';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { networkInterfaces } from 'node:os';
import { afterAll, beforeAll, expect, test } from 'vitest';

// Prometheus scrapes the pod's address, not localhost.
const address = Object.values(networkInterfaces())
	.flat()
	.find((i) => i && i.family === 'IPv4' && !i.internal)?.address;

// Stands in for the collector: counts the trace exports it gets.
let exports = 0;
let collector: Server;

beforeAll(async () => {
	collector = createServer((req, res) => {
		if (req.url === '/v1/traces') exports++;
		req.resume().on('end', () => res.end());
	});
	await new Promise<void>((r) => collector.listen(0, '127.0.0.1', r));
	process.env.OTEL_EXPORTER_OTLP_ENDPOINT = `http://127.0.0.1:${(collector.address() as AddressInfo).port}`;
	process.env.METRICS_PORT = '19464';
	await import('./instrumentation.server');
});

afterAll(() => {
	process.emit('sveltekit:shutdown' as 'exit', 0);
	collector.close();
});

test.skipIf(!address)('metrics answer on the pod address, not only on localhost', async () => {
	let res: Response | undefined;
	for (let i = 0; i < 20 && !res; i++) {
		res = await fetch(`http://${address}:19464/metrics`).catch(() => undefined);
		if (!res) await new Promise((r) => setTimeout(r, 100));
	}
	expect(res?.status).toBe(200);
});

test('a span inside another is its child, carries on across awaits, and goes out as traceparent', async () => {
	const tracer = trace.getTracer('test');
	await tracer.startActiveSpan('request', async (parent) => {
		await new Promise((r) => setTimeout(r, 1));
		const child = tracer.startSpan('load');
		expect(child.spanContext().traceId).toBe(parent.spanContext().traceId);
		expect(trace.getActiveSpan()).toBe(parent);

		const headers: Record<string, string> = {};
		propagation.inject(context.active(), headers);
		expect(headers.traceparent).toContain(parent.spanContext().traceId);
		child.end();
		parent.end();
	});

	const provider = (
		trace.getTracerProvider() as ProxyTracerProvider
	).getDelegate() as TracerProvider;
	await provider.forceFlush();
	expect(exports).toBeGreaterThan(0);
});
