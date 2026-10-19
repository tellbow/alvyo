import type { RasterDEMSourceSpecification, StyleSpecification } from 'maplibre-gl';
import { TILE_PROTOCOL } from './tiles';

/** Switzerland and Liechtenstein with a margin: no tiles are requested outside. */
export const CH_BOUNDS: [number, number, number, number] = [5.7, 45.6, 10.8, 48.0];
export const CH_CENTER: [number, number] = [8.23, 46.82];

export const SWISSTOPO_ATTRIBUTION =
	'<a href="https://www.swisstopo.admin.ch/" target="_blank" rel="noopener">© swisstopo</a>';
/** Routes are computed on OpenStreetMap; huts, places and points of interest come from it. */
export const OSM_ATTRIBUTION =
	'<a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">© OpenStreetMap contributors</a>';
const ASTRA_ATTRIBUTION =
	'<a href="https://www.schweizmobil.ch/" target="_blank" rel="noopener">© ASTRA, SchweizMobil</a>';
const BAFU_ATTRIBUTION =
	'<a href="https://www.bafu.admin.ch/" target="_blank" rel="noopener">© BAFU</a>';
/** The heights behind the reach areas' slopes (GraphHopper's elevation from Mapzen's terrain tiles). */
export const TERRAIN_TILES_ATTRIBUTION =
	'<a href="https://github.com/tilezen/joerd/blob/master/docs/attribution.md" target="_blank" rel="noopener">Terrain Tiles: Mapzen, EU-DEM (Copernicus), SRTM (USGS)</a>';

export type BaseMapId = 'landeskarte' | 'landeskarte_grau' | 'luftbild' | 'basemap';
export type RasterOverlayId =
	'wanderwege' | 'wanderland' | 'hangneigung' | 'wildruhezonen' | 'jagdbanngebiete' | 'relief';
/** Huts and accommodation from our places, drawn as points. */
export type PlaceOverlayId = 'huts' | 'lodging' | 'pois';
/** Rain: radar and forecast with a timeline (PrecipLayer); snow cover (SnowLayer). */
export type WeatherOverlayId = 'precip' | 'snow';
export type OverlayId = RasterOverlayId | PlaceOverlayId | WeatherOverlayId;

export const BASE_MAPS: BaseMapId[] = ['landeskarte', 'landeskarte_grau', 'luftbild', 'basemap'];
export const OVERLAYS: OverlayId[] = [
	'wanderwege',
	'wanderland',
	'hangneigung',
	'wildruhezonen',
	'jagdbanngebiete',
	'relief',
	'precip',
	'snow',
	'huts',
	'lodging',
	'pois'
];

/** swisstopo WMTS layers (EPSG:3857) served through our tile cache. */
/** The federal offices' layers credit their office (BAFU, ASTRA); swisstopo's are in the base attribution. */
const RASTER: Record<
	string,
	{ layer: string; ext: 'jpeg' | 'png'; maxzoom: number; attribution?: string }
> = {
	landeskarte: { layer: 'ch.swisstopo.pixelkarte-farbe', ext: 'jpeg', maxzoom: 19 },
	landeskarte_grau: { layer: 'ch.swisstopo.pixelkarte-grau', ext: 'jpeg', maxzoom: 19 },
	luftbild: { layer: 'ch.swisstopo.swissimage', ext: 'jpeg', maxzoom: 20 },
	wanderwege: { layer: 'ch.swisstopo.swisstlm3d-wanderwege', ext: 'png', maxzoom: 18 },
	wanderland: {
		layer: 'ch.astra.wanderland',
		ext: 'png',
		maxzoom: 18,
		attribution: ASTRA_ATTRIBUTION
	},
	hangneigung: { layer: 'ch.swisstopo.hangneigung-ueber_30', ext: 'png', maxzoom: 17 },
	wildruhezonen: {
		layer: 'ch.bafu.wrz-wildruhezonen_portal',
		ext: 'png',
		maxzoom: 18,
		attribution: BAFU_ATTRIBUTION
	},
	jagdbanngebiete: {
		layer: 'ch.bafu.bundesinventare-jagdbanngebiete',
		ext: 'png',
		maxzoom: 18,
		attribution: BAFU_ATTRIBUTION
	},
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
		bounds: CH_BOUNDS,
		...(r.attribution ? { attribution: r.attribution } : {})
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

export function overlaySource(id: RasterOverlayId, origin: string) {
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
		layers: [...next.layers, ...overlays, ...routes],
		...(previous.terrain ? { terrain: previous.terrain } : {})
	};
}

/** The terrain for 3D: Mapterhorn's open terrain tiles, through the tile cache. */
export const TERRAIN_SOURCE = OVERLAY_PREFIX + 'terrain';

export function terrainSource(origin: string): RasterDEMSourceSpecification {
	return {
		type: 'raster-dem',
		tiles: [`${TILE_PROTOCOL}://${origin}/tiles/terrain/{z}/{x}/{y}.webp`],
		encoding: 'terrarium',
		tileSize: 512,
		maxzoom: 14,
		attribution:
			'<a href="https://mapterhorn.com/attribution" target="_blank" rel="noopener">© Mapterhorn</a>'
	};
}
