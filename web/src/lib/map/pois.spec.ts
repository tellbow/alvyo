import { describe, expect, it } from 'vitest';
import { poiText } from './places';

describe('points of interest', () => {
	it('names a summit with its height, and water without a name by its kind', () => {
		expect(poiText({ kind: 'peak', name: 'Reeti', ele: 2757 })).toEqual([
			'Reeti',
			'Gipfel · 2757 m'
		]);
		expect(poiText({ kind: 'water', name: '' })).toEqual(['Trinkwasser', '']);
		expect(poiText({ kind: 'viewpoint', name: 'Bänkli' })).toEqual(['Bänkli', 'Aussichtspunkt']);
	});
});
