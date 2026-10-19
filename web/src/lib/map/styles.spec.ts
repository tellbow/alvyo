import { describe, expect, it } from 'vitest';
import type { StyleSpecification } from 'maplibre-gl';
import { baseStyle, failing, fromVectorBase, keepOwnLayers, overlaySource } from './styles';

const style = (layers: string[], sources: string[]): StyleSpecification => ({
	version: 8,
	sources: Object.fromEntries(sources.map((s) => [s, { type: 'raster', tiles: [s] }])),
	layers: layers.map((id) => ({ id, type: 'raster', source: id }))
});

describe('keepOwnLayers', () => {
	it('carries overlays and routes to the new base map in order', () => {
		const prev = style(
			['base', 'route-line', 'ovl-wanderwege'],
			['base', 'route-line', 'ovl-wanderwege']
		);
		const next = style(['water', 'labels'], ['vt']);
		const out = keepOwnLayers(prev, next);
		expect(out.layers.map((l) => l.id)).toEqual([
			'water',
			'labels',
			'ovl-wanderwege',
			'route-line'
		]);
		expect(Object.keys(out.sources).sort()).toEqual(['ovl-wanderwege', 'route-line', 'vt']);
	});

	it('returns the next style unchanged on first load', () => {
		const next = style(['a'], ['a']);
		expect(keepOwnLayers(undefined, next)).toBe(next);
	});
});

describe('baseStyle', () => {
	it('serves raster base maps through the tile cache, limited to Switzerland', () => {
		const s = baseStyle('landeskarte', 'https://alvyo.ch') as StyleSpecification;
		const src = s.sources.base as { tiles: string[]; bounds: number[] };
		expect(src.tiles[0]).toBe(
			'alvyo-tile://https://alvyo.ch/tiles/wmts/ch.swisstopo.pixelkarte-farbe/{z}/{x}/{y}.jpeg'
		);
		expect(src.bounds).toEqual([5.7, 45.6, 10.8, 48.0]);
	});
});

describe('overlaySource', () => {
	it('credits the federal office of each overlay', () => {
		expect(overlaySource('wanderland', 'https://a.test').attribution).toContain('ASTRA');
		expect(overlaySource('wildruhezonen', 'https://a.test').attribution).toContain('BAFU');
		expect(overlaySource('jagdbanngebiete', 'https://a.test').attribution).toContain('BAFU');
		// swisstopo's layers are credited by the map's own attribution.
		expect(overlaySource('wanderwege', 'https://a.test').attribution).toBeUndefined();
	});
});

describe('fromVectorBase', () => {
	it('counts the vector base map’s own sources and requests to swisstopo’s vector tiles', () => {
		expect(fromVectorBase({ sourceId: 'base_v1.0.0' })).toBe(true);
		expect(
			fromVectorBase({
				error: { url: 'https://vectortiles.geo.admin.ch/styles/ch.swisstopo.basemap.vt/style.json' }
			})
		).toBe(true);
		expect(
			fromVectorBase({
				error: {
					url: 'https://vectortiles3.geo.admin.ch/tiles/ch.swisstopo.base.vt/v1.0.0/9/267/180.pbf'
				}
			})
		).toBe(true);
	});

	it('leaves out our overlays, routes and other errors', () => {
		expect(fromVectorBase({ sourceId: 'ovl-terrain' })).toBe(false);
		expect(fromVectorBase({ sourceId: 'route-line' })).toBe(false);
		expect(fromVectorBase({ error: { url: 'https://alvyo.ch/tiles/wmts/x/1/2/3.png' } })).toBe(
			false
		);
		expect(fromVectorBase({ error: new Error('An image named "poi-peak" already exists.') })).toBe(
			false
		);
	});
});

describe('failing', () => {
	it('is true at the fifth failure within a minute', () => {
		const times: number[] = [];
		for (const t of [0, 10_000, 20_000, 30_000]) expect(failing(times, t)).toBe(false);
		expect(failing(times, 59_000)).toBe(true);
	});

	it('forgets failures older than a minute', () => {
		const times: number[] = [];
		for (const t of [0, 20_000, 40_000, 60_000, 80_000]) expect(failing(times, t)).toBe(false);
		expect(times).toEqual([40_000, 60_000, 80_000]);
	});
});
