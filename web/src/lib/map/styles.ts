import type { StyleSpecification } from 'maplibre-gl';
import { TILE_PROTOCOL } from './tiles';

/** Switzerland and Liechtenstein with a margin: no tiles are requested outside. */
export const CH_BOUNDS: [number, number, number, number] = [5.7, 45.6, 10.8, 48.0];
export const CH_CENTER: [number, number] = [8.23, 46.82];

export const SWISSTOPO_ATTRIBUTION =
	'<a href="https://www.swisstopo.admin.ch/" target="_blank" rel="noopener">© swisstopo</a>';

export type BaseMapId = 'landeskarte' | 'landeskarte_grau' | 'luftbild' | 'basemap';
export type OverlayId =
	'wanderwege' | 'wanderland' | 'hangneigung' | 'wildruhezonen' | 'jagdbanngebiete' | 'relief';

export const BASE_MAPS: BaseMapId[] = ['landeskarte', 'landeskarte_grau', 'luftbild', 'basemap'];
export const OVERLAYS: OverlayId[] = [
	'wanderwege',
	'wanderland',
	'hangneigung',
	'wildruhezonen',
	'jagdbanngebiete',
	'relief'
];

/** swisstopo WMTS layers (EPSG:3857) served through our tile cache. */
const RASTER: Record<string, { layer: string; ext: 'jpeg' | 'png'; maxzoom: number }> = {
	landeskarte: { layer: 'ch.swisstopo.pixelkarte-farbe', ext: 'jpeg', maxzoom: 19 },
	landeskarte_grau: { layer: 'ch.swisstopo.pixelkarte-grau', ext: 'jpeg', maxzoom: 19 },
	luftbild: { layer: 'ch.swisstopo.swissimage', ext: 'jpeg', maxzoom: 20 },
	wanderwege: { layer: 'ch.swisstopo.swisstlm3d-wanderwege', ext: 'png', maxzoom: 18 },
	wanderland: { layer: 'ch.astra.wanderland', ext: 'png', maxzoom: 18 },
	hangneigung: { layer: 'ch.swisstopo.hangneigung-ueber_30', ext: 'png', maxzoom: 17 },
	wildruhezonen: { layer: 'ch.bafu.wrz-wildruhezonen_portal', ext: 'png', maxzoom: 18 },
	jagdbanngebiete: { layer: 'ch.bafu.bundesinventare-jagdbanngebiete', ext: 'png', maxzoom: 18 },
	relief: { layer: 'ch.swisstopo.swissalti3d-reliefschattierung', ext: 'png', maxzoom: 18 }
};

const VECTOR_STYLE = 'https://vectortiles.geo.admin.ch/styles/ch.swisstopo.basemap.vt/style.json';

function rasterSource(id: string, origin: string) {
	const r = RASTER[id];
	return {
		type: 'raster' as const,
		tiles: [`${TILE_PROTOCOL}://${origin}/tiles/wmts/${r.layer}/{z}/{x}/{y}.${r.ext}`],
		tileSize: 256,
		maxzoom: r.maxzoom,
		bounds: CH_BOUNDS
	};
}

/** The style (object or URL) of a base map. `origin` is the page origin. */
export function baseStyle(id: BaseMapId, origin: string): StyleSpecification | string {
	if (id === 'basemap') return VECTOR_STYLE;
	return {
		version: 8,
		glyphs: 'https://vectortiles.geo.admin.ch/fonts/{fontstack}/{range}.pbf',
		sources: { base: rasterSource(id, origin) },
		layers: [{ id: 'base', type: 'raster', source: 'base' }]
	};
}

/** Prefix of sources and layers we add on top of any base map. */
export const OVERLAY_PREFIX = 'ovl-';
export const ROUTE_PREFIX = 'route-';

export function overlaySource(id: OverlayId, origin: string) {
	return rasterSource(id, origin);
}

/**
 * Keeps our own sources and layers (overlays, routes) when the base map
 * changes: used as `transformStyle` in `map.setStyle`.
 */
export function keepOwnLayers(
	previous: StyleSpecification | undefined,
	next: StyleSpecification
): StyleSpecification {
	if (!previous) return next;
	const own = (id: string) => id.startsWith(OVERLAY_PREFIX) || id.startsWith(ROUTE_PREFIX);
	const sources = Object.fromEntries(Object.entries(previous.sources).filter(([id]) => own(id)));
	const layers = previous.layers.filter((l) => own(l.id));
	// Overlays go directly above the base map, routes on top of everything.
	const overlays = layers.filter((l) => l.id.startsWith(OVERLAY_PREFIX));
	const routes = layers.filter((l) => l.id.startsWith(ROUTE_PREFIX));
	return {
		...next,
		sources: { ...next.sources, ...sources },
		layers: [...next.layers, ...overlays, ...routes]
	};
}
