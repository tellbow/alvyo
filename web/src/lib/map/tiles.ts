import type { AddProtocolAction } from 'maplibre-gl';

/**
 * Raster tiles are loaded through this protocol: `odysgeh-tile://` followed
 * by the real URL. A tile the tile cache refuses while busy (many at once
 * when zooming) is asked for again, a little later each time; MapLibre would
 * otherwise show another zoom level in its place until the map moves.
 */
export const TILE_PROTOCOL = 'odysgeh-tile';

const RETRIES = 3;

export function tileLoader(fetchFn: typeof fetch = fetch, delayMs = 1000): AddProtocolAction {
	return async (params, abort) => {
		const url = params.url.slice(TILE_PROTOCOL.length + 3);
		for (let attempt = 0; ; attempt++) {
			const res = await fetchFn(url, { signal: abort.signal });
			if (res.ok) {
				return {
					data: await res.arrayBuffer(),
					cacheControl: res.headers.get('cache-control'),
					expires: res.headers.get('expires')
				};
			}
			const busy = res.status === 429 || res.status >= 500;
			if (!busy || attempt === RETRIES) throw new Error(`tile ${res.status}: ${url}`);
			await wait(delayMs * (attempt + 1), abort.signal);
		}
	};
}

function wait(ms: number, signal: AbortSignal) {
	return new Promise<void>((resolve, reject) => {
		const t = setTimeout(resolve, ms);
		signal.addEventListener('abort', () => {
			clearTimeout(t);
			reject(signal.reason);
		});
	});
}
