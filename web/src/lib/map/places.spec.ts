import { describe, expect, it } from 'vitest';
import { placeFeatures, placeKinds, webLink } from './places';

describe('placeKinds', () => {
	it('asks only for the chosen overlays from their zoom on', () => {
		expect(placeKinds(['wanderwege'], 12)).toEqual([]);
		expect(placeKinds(['huts', 'lodging'], 7)).toEqual([]);
		expect(placeKinds(['huts', 'lodging'], 9)).toEqual(['hut']);
		expect(placeKinds(['lodging', 'huts'], 10)).toEqual(['hut', 'hotel', 'campsite']);
	});

	it('asks along the way only for the kinds switched on', () => {
		expect(placeKinds(['pois'], 11)).toEqual([]);
		expect(placeKinds(['pois'], 12)).toHaveLength(10);
		expect(placeKinds(['pois', 'huts'], 12, ['water', 'firepit'])).toEqual([
			'hut',
			'water',
			'firepit'
		]);
		expect(placeKinds(['pois'], 12, [])).toEqual([]);
	});
});

describe('placeFeatures', () => {
	it('makes points with the fields the popup needs', () => {
		const fc = placeFeatures([
			{ id: 'a', kind: 'hut', name: 'Hütte', detail: 'alpine_hut', lon: 9.2, lat: 46.5 }
		]);
		expect(fc.features[0].geometry.coordinates).toEqual([9.2, 46.5]);
		expect(fc.features[0].properties).toEqual({
			id: 'a',
			kind: 'hut',
			name: 'Hütte',
			detail: 'alpine_hut',
			website: ''
		});
	});
});

describe('webLink', () => {
	it('keeps only http(s) addresses', () => {
		expect(webLink('https://www.sac-cas.ch')).toBe('https://www.sac-cas.ch/');
		expect(webLink('http://huette.ch/x')).toBe('http://huette.ch/x');
		expect(webLink('javascript:alert(1)')).toBeUndefined();
		expect(webLink('www.huette.ch')).toBeUndefined();
		expect(webLink('')).toBeUndefined();
		expect(webLink(undefined)).toBeUndefined();
	});
});
