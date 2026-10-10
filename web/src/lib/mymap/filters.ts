import { readDone, type DoneFilter } from '#lib/done/done.js';

export type Kind = 'route' | 'journey' | 'hike';
export const KINDS: Kind[] = ['route', 'journey', 'hike'];

/** The filters of the map of one's hikes, as shown (km, hours at one's pace). */
export type Filters = {
	kinds: Kind[]; // none: all
	done: DoneFilter; // planned or hiked only; '': all
	tags: string[]; // any of them; none: all
	distance: [number | undefined, number | undefined]; // km
	duration: [number | undefined, number | undefined]; // h
	sac: [number, number]; // 0: open
	longest: boolean;
	shared: boolean;
	color: 'kind' | 'sac';
};

const positive = (v: string | null) => {
	const n = Number(v);
	return v && Number.isFinite(n) && n > 0 ? n : undefined;
};
const grade = (v: string | null) => Math.min(Math.max(Math.round(Number(v)) || 0, 0), 6);

/** Filters from the page address. */
export function readFilters(p: Pick<URLSearchParams, 'get' | 'getAll'>): Filters {
	return {
		kinds: (p.get('kind') ?? '').split(',').filter((k): k is Kind => KINDS.includes(k as Kind)),
		done: readDone(p),
		tags: p.getAll('tag').filter(Boolean),
		distance: [positive(p.get('dmin')), positive(p.get('dmax'))],
		duration: [positive(p.get('tmin')), positive(p.get('tmax'))],
		sac: [grade(p.get('sacmin')), grade(p.get('sacmax'))],
		longest: p.get('longest') === '1',
		shared: p.get('shared') === '1',
		color: p.get('color') === 'sac' ? 'sac' : 'kind'
	};
}

/** The page address for filters, to bookmark them (only what is set). */
export function writeFilters(f: Filters, bbox: string): URLSearchParams {
	const q = new URLSearchParams({ bbox });
	const set = (k: string, v: number | string | undefined | false) => {
		if (v) q.set(k, String(v));
	};
	set('kind', f.kinds.join(','));
	set('done', f.done);
	for (const t of f.tags) q.append('tag', t);
	set('dmin', f.distance[0]);
	set('dmax', f.distance[1]);
	set('tmin', f.duration[0]);
	set('tmax', f.duration[1]);
	set('sacmin', f.sac[0]);
	set('sacmax', f.sac[1]);
	set('longest', f.longest && '1');
	set('shared', f.shared && '1');
	set('color', f.color === 'sac' && 'sac');
	return q;
}

/** The API query for filters; hours at the given pace become Swiss hiking time. */
export function apiQuery(f: Filters, pace: number) {
	const metres = (km?: number) => (km ? Math.round(km * 1000) : undefined);
	const seconds = (h?: number) => (h ? Math.round((h * 3600) / pace) : undefined);
	return {
		kind: f.kinds.length ? f.kinds : undefined,
		done: f.done || undefined,
		tags: f.tags.length ? f.tags : undefined,
		distance_min: metres(f.distance[0]),
		distance_max: metres(f.distance[1]),
		duration_min: seconds(f.duration[0]),
		duration_max: seconds(f.duration[1]),
		sac_min: f.sac[0] || undefined,
		sac_max: f.sac[1] || undefined,
		longest_stage: f.longest || undefined,
		shared: f.shared || undefined
	};
}
