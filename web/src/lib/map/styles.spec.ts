import { describe, expect, it } from 'vitest';
import type { StyleSpecification } from 'maplibre-gl';
import { baseStyle, keepOwnLayers } from './styles';

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
		const s = baseStyle('landeskarte', 'https://odysgeh.ch') as StyleSpecification;
		const src = s.sources.base as { tiles: string[]; bounds: number[] };
		expect(src.tiles[0]).toBe(
			'odysgeh-tile://https://odysgeh.ch/tiles/wmts/ch.swisstopo.pixelkarte-farbe/{z}/{x}/{y}.jpeg'
		);
		expect(src.bounds).toEqual([5.7, 45.6, 10.8, 48.0]);
	});
});
