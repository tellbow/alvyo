import type { PlannerContent } from './planner.svelte';
import type { Profile } from './route';

export type QueryPoint = { at: [number, number]; name?: string };

const coord = (at: [number, number]) => `${at[0].toFixed(5)},${at[1].toFixed(5)}`;

/**
 * The planner's query for a route from `from` to `to`, e.g. from
 * «Reichweite»: `?from=lon,lat&to=lon,lat&profile=…` and the start's name.
 */
export function planQuery(from: QueryPoint, to: [number, number], profile: Profile): string {
	const q = new URLSearchParams({ from: coord(from.at), to: coord(to), profile });
	if (from.name) q.set('from_name', from.name);
	return q.toString();
}

/** The points and profile of a planner query, if it has both points. */
export function readPlanQuery(q: URLSearchParams): Omit<PlannerContent, 'legs'> | undefined {
	const point = (key: 'from' | 'to') => {
		const [lon, lat] = (q.get(key) ?? '').split(',').map(Number);
		if (!Number.isFinite(lon) || !Number.isFinite(lat)) return undefined;
		return { lon, lat };
	};
	const from = point('from');
	const to = point('to');
	if (!from || !to) return undefined;
	const name = q.get('from_name');
	return {
		profile: q.get('profile') === 'alpine' ? 'alpine' : 'hike',
		anchors: [name ? { ...from, name } : from, to]
	};
}
