import type { Journey } from '$lib/api/client';

/** The stops of a public transport transfer from the previous stage's end. */
export function transferStops(journey: Journey, i: number) {
	const s = journey.stage_list[i];
	if (s.transfer_before !== 'pt' || s.start_place?.kind !== 'pt_stop') return undefined;
	const prev = journey.stage_list.slice(0, i).findLast((p) => p.route)?.end_place;
	if (prev?.kind !== 'pt_stop') return undefined;
	return { from: prev, to: s.start_place };
}
