import type { Proposal } from '#lib/api/client.js';
import { combine } from '#lib/planner/route.js';

/** What the map and the profile show of a proposal; breaks: where each stage starts. */
export function stageView(p: Proposal) {
	const breaks: number[] = [];
	let n = 0;
	for (const st of p.stages) {
		breaks.push(Math.max(n - 1, 0));
		for (const l of st.legs) n += n === 0 ? l.coordinates.length : l.coordinates.length - 1;
	}
	return {
		lines: p.stages.map((st) => st.legs.flatMap((l) => l.coordinates)),
		profile: combine(p.stages.flatMap((st) => st.legs)),
		breaks
	};
}

/** Where the days end, as the API takes it: a place's id, or `@lon/lat` for a spot on the line. */
export function stageEnds(p: Proposal): string[] {
	return p.stages.slice(0, -1).map((st) => {
		if (st.end_place) return st.end_place.id;
		const end = st.legs.at(-1)!.coordinates.at(-1)!;
		return `@${end[0]}/${end[1]}`;
	});
}

/** The ends with one more, in stage k (0 is the first) at the spot. */
export function endsWithSpot(p: Proposal, k: number, lon: number, lat: number): string[] {
	return stageEnds(p).toSpliced(k, 0, `@${lon}/${lat}`);
}

/** The body of `POST /journeys` for a proposal, private. */
export function journeyBody(title: string, p: Proposal) {
	return {
		title,
		visibility: 'private' as const,
		stages: p.stages.map((st) => ({
			profile: st.profile as 'hike' | 'alpine',
			anchors: st.anchors,
			legs: st.legs,
			accommodation: st.accommodation,
			...(st.start_place ? { start_place_id: st.start_place.id } : {}),
			...(st.end_place ? { end_place_id: st.end_place.id } : {})
		}))
	};
}
