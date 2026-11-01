import { describe, expect, it } from 'vitest';
import type { Proposal } from '#lib/api/client.js';
import { endsWithSpot, stageEnds } from './stages';

const stage = (lon: number, place?: string) => ({
	end_place: place ? { id: place } : null,
	legs: [
		{
			coordinates: [
				[lon - 1, 46, 500],
				[lon, 46.5, 600]
			]
		}
	]
});
const proposal = { stages: [stage(8, 'hut'), stage(9), stage(10)] } as unknown as Proposal;

describe('stage ends', () => {
	it('names a place by its id and a spot by the end of the stage, not the last stage', () => {
		expect(stageEnds(proposal)).toEqual(['hut', '@9/46.5']);
	});
	it('puts a new end in the stage it splits', () => {
		expect(endsWithSpot(proposal, 0, 7.5, 46.2)).toEqual(['@7.5/46.2', 'hut', '@9/46.5']);
		expect(endsWithSpot(proposal, 2, 9.5, 46.2)).toEqual(['hut', '@9/46.5', '@9.5/46.2']);
	});
});
