import { describe, expect, it } from 'vitest';
import { groupPois, poiText, type Poi } from './places';

describe('points of interest', () => {
	it('names a summit with its height, and water without a name by its kind', () => {
		expect(poiText({ kind: 'peak', name: 'Reeti', ele: 2757 })).toEqual([
			'Reeti',
			'Gipfel · 2757 m'
		]);
		expect(poiText({ kind: 'water', name: '' })).toEqual(['Trinkwasser', '']);
		expect(poiText({ kind: 'viewpoint', name: 'Bänkli' })).toEqual(['Bänkli', 'Aussichtspunkt']);
	});

	it('lists the fountains and restaurants of a town together, summits one each', () => {
		const p = (kind: Poi['kind'], along_m: number, name = ''): Poi => ({
			kind,
			name,
			at: [9.4, 47],
			along_m
		});
		const rows = groupPois([
			p('restaurant', 31, 'Perron'),
			p('water', 71),
			p('water', 73),
			p('restaurant', 111, 'Capannina'),
			p('peak', 500, 'Gonzen'),
			p('peak', 520, 'Alvier'),
			p('water', 1000),
			p('water', 1100), // more than 1 km after the first: a new line
			p('restaurant', 2500, 'Kivi')
		]);
		expect(rows.map((r) => [r.kind, r.count, r.along_m, r.to_m, r.name])).toEqual([
			['restaurant', 2, 31, 111, 'Perron'],
			['water', 3, 71, 1000, ''],
			['peak', 1, 500, 500, 'Gonzen'],
			['peak', 1, 520, 520, 'Alvier'],
			['water', 1, 1100, 1100, ''],
			['restaurant', 1, 2500, 2500, 'Kivi']
		]);
	});
});
