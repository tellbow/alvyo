import type { PlanStage, Proposal } from '$lib/api/client';

/** A suggested way, as far as putting a journey together needs it. */
export type Way = { proposal: Pick<Proposal, 'stages'> };

/** A day of the journey being put together: the way and its day. */
export type Picked = { way: number; stage: number };

/** All days of one way. */
export function whole(ways: Way[], way: number): Picked[] {
	return ways[way].proposal.stages.map((_, stage) => ({ way, stage }));
}

/** The days' stages. */
export function stagesOf(ways: Way[], picked: Picked[]): PlanStage[] {
	return picked.map((p) => ways[p.way].proposal.stages[p.stage]);
}

/** The one way all days come from; undefined when put together. */
export function single(ways: Way[], picked: Picked[]): number | undefined {
	const w = picked[0]?.way;
	return w !== undefined &&
		picked.length === whole(ways, w).length &&
		picked.every((p) => p.way === w)
		? w
		: undefined;
}

/**
 * The other ways that sleep where day i ends, each with its day ending
 * there: the journey can go on along them.
 */
export function switches(ways: Way[], picked: Picked[], i: number): Picked[] {
	const p = picked[i];
	const end = ways[p.way].proposal.stages[p.stage].end_place?.id;
	if (!end) return [];
	const out: Picked[] = [];
	ways.forEach((w, way) => {
		if (way === p.way) return;
		const stage = w.proposal.stages.findIndex((st) => st.end_place?.id === end);
		if (stage >= 0) out.push({ way, stage });
	});
	return out;
}

/** The days up to day i, then along the way of `to` after its day. */
export function switchTo(ways: Way[], picked: Picked[], i: number, to: Picked): Picked[] {
	return [...picked.slice(0, i + 1), ...whole(ways, to.way).slice(to.stage + 1)];
}
