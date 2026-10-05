import { describe, expect, it } from 'vitest';
import { apiQuery, readFilters, writeFilters } from './filters';

describe('map filters', () => {
	it('survive the address', () => {
		const q = new URLSearchParams(
			'bbox=7,46,8,47&kind=route,hike,bogus&done=planned&tag=Winter&tag=mit%2C+Kindern&dmin=5&tmax=4.5&sacmin=2&sacmax=9&shared=1&color=sac'
		);
		const f = readFilters(q);
		expect(f).toEqual({
			kinds: ['route', 'hike'],
			done: 'planned',
			tags: ['Winter', 'mit, Kindern'],
			distance: [5, undefined],
			duration: [undefined, 4.5],
			sac: [2, 6],
			longest: false,
			shared: true,
			color: 'sac'
		});
		expect(readFilters(writeFilters(f, '7,46,8,47'))).toEqual(f);
		expect(writeFilters(readFilters(new URLSearchParams()), 'b').toString()).toBe('bbox=b');
	});

	it('become an API query at the pace of the hiker', () => {
		const f = readFilters(new URLSearchParams('dmin=2.5&tmin=2&tmax=4'));
		expect(apiQuery(f, 2)).toMatchObject({
			distance_min: 2500,
			duration_min: 3600,
			duration_max: 7200,
			kind: undefined,
			sac_min: undefined
		});
	});
});
