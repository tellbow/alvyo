import { networkInterfaces } from 'node:os';
import { afterAll, expect, test } from 'vitest';

// Prometheus scrapes the pod's address, not localhost.
const address = Object.values(networkInterfaces())
	.flat()
	.find((i) => i && i.family === 'IPv4' && !i.internal)?.address;

afterAll(() => {
	process.emit('sveltekit:shutdown' as 'exit', 0);
});

test.skipIf(!address)('metrics answer on the pod address, not only on localhost', async () => {
	process.env.METRICS_PORT = '19464';
	delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
	await import('./instrumentation.server');
	let res: Response | undefined;
	for (let i = 0; i < 20 && !res; i++) {
		res = await fetch(`http://${address}:19464/metrics`).catch(() => undefined);
		if (!res) await new Promise((r) => setTimeout(r, 100));
	}
	expect(res?.status).toBe(200);
});
