import { describe, expect, it } from 'vitest';
import { tileLoader } from './tiles';

const url = 'odysgeh-tile://https://odysgeh.ch/tiles/wmts/l/10/1/2.png';

function server(statuses: number[]) {
	const asked: string[] = [];
	const fetchFn = (async (u: string) => {
		asked.push(u);
		return new Response(new Uint8Array([1, 2, 3]), { status: statuses.shift() ?? 200 });
	}) as typeof fetch;
	return { asked, fetchFn };
}

describe('tileLoader', () => {
	it('asks again for a tile refused while busy', async () => {
		const { asked, fetchFn } = server([503, 429]);
		const res = await tileLoader(fetchFn, 1)({ url }, new AbortController());
		expect(asked).toEqual(Array(3).fill('https://odysgeh.ch/tiles/wmts/l/10/1/2.png'));
		expect((res.data as ArrayBuffer).byteLength).toBe(3);
	});

	it('gives up after three retries, and at once on other errors', async () => {
		const busy = server([503, 503, 503, 503, 503]);
		await expect(tileLoader(busy.fetchFn, 1)({ url }, new AbortController())).rejects.toThrow(
			'503'
		);
		expect(busy.asked).toHaveLength(4);
		const missing = server([404]);
		await expect(tileLoader(missing.fetchFn, 1)({ url }, new AbortController())).rejects.toThrow(
			'404'
		);
		expect(missing.asked).toHaveLength(1);
	});

	it('stops waiting when the tile is no longer needed', async () => {
		const { asked, fetchFn } = server([503]);
		const abort = new AbortController();
		const loading = tileLoader(fetchFn, 60_000)({ url }, abort);
		setTimeout(() => abort.abort(), 10);
		await expect(loading).rejects.toThrow();
		expect(asked).toHaveLength(1);
	});
});
