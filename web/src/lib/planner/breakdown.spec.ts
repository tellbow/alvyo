import { describe, expect, it } from 'vitest';
import { breakdownParts, legendParts } from './breakdown';

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

describe('legendParts', () => {
	it('keeps the three largest and sums the rest', () => {
		const parts = [0.05, 0.5, 0.02, 0.3, 0.13].map((share, i) => ({ key: `k${i}`, share }));
		const { top, other } = legendParts(parts);
		expect(top.map((p) => p.key)).toEqual(['k1', 'k3', 'k4']);
		expect(other).toBeCloseTo(0.07);
	});

	it('has no rest when there are three or fewer', () => {
		expect(legendParts([{ share: 1 }]).other).toBe(0);
	});
});
