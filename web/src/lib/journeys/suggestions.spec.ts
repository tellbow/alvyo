import { describe, expect, it } from 'vitest';
import type { PlanStage } from '$lib/api/client';
import { single, stagesOf, switches, switchTo, whole, type Way } from './suggestions';

/** A way whose days end at the given places; null for the destination. */
function way(...ends: (string | null)[]): Way {
	return {
		proposal: {
			stages: ends.map((id) => ({ end_place: id ? { id, name: id } : null }) as PlanStage)
		}
	};
}

// Thun → Zermatt: over the Lötschenpass, or over the Gemmi; both sleep in
// Gampel on the third night. A third way meets neither.
const ways = [
	way('Kandersteg', 'Gfellalp', 'Gampel', 'Kalpetran', null),
	way('Kandersteg', 'Gemmi', 'Gampel', 'St. Niklaus', null),
	way('Adelboden', 'Sierre', 'Gruben', null)
];

describe('suggestions', () => {
	it('knows the ways that sleep at the same place', () => {
		const picked = whole(ways, 0);
		expect(switches(ways, picked, 0)).toEqual([{ way: 1, stage: 0 }]);
		expect(switches(ways, picked, 1)).toEqual([]);
		expect(switches(ways, picked, 2)).toEqual([{ way: 1, stage: 2 }]);
		// The last day ends at the destination: nothing to change to.
		expect(switches(ways, picked, 4)).toEqual([]);
	});

	it('goes on along another way', () => {
		// Over the Lötschenpass to Gampel, then as the Gemmi way goes on.
		const picked = switchTo(ways, whole(ways, 0), 2, { way: 1, stage: 2 });
		expect(stagesOf(ways, picked).map((st) => st.end_place?.id ?? null)).toEqual([
			'Kandersteg',
			'Gfellalp',
			'Gampel',
			'St. Niklaus',
			null
		]);
		expect(single(ways, picked)).toBeUndefined();
		// And back along the first way from Kandersteg: all its days again.
		expect(single(ways, switchTo(ways, picked, 0, { way: 0, stage: 0 }))).toBe(0);
	});

	it('changes at a night the ways reach on different days', () => {
		const a = way('A', 'B', null);
		const b = way('B', 'C', 'D', null);
		const picked = switchTo([a, b], whole([a, b], 0), 1, { way: 1, stage: 0 });
		expect(stagesOf([a, b], picked).map((st) => st.end_place?.id ?? null)).toEqual([
			'A',
			'B',
			'C',
			'D',
			null
		]);
	});
});
