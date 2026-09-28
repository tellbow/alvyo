import { describe, expect, it } from 'vitest';
import { breakdownParts } from './breakdown';

describe('breakdownParts', () => {
	const keys = ['paved', 'gravel', 'unknown'];

	it('gives the shares of what is there', () => {
		expect(breakdownParts({ paved: 300, unknown: 100 }, keys, 'unknown')).toEqual([
			{ key: 'paved', metres: 300, share: 0.75 },
			{ key: 'unknown', metres: 100, share: 0.25 }
		]);
	});

	it('shows nothing when only the unknown is known', () => {
		expect(breakdownParts({ unknown: 19_300 }, keys, 'unknown')).toEqual([]);
		expect(breakdownParts({}, keys, 'unknown')).toEqual([]);
	});

	it('keeps a breakdown without an unknown part', () => {
		expect(breakdownParts({ none: 10 }, ['Wanderweg', 'none'])).toHaveLength(1);
	});
});
