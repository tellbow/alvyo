import type { Leg } from '$lib/api/client';
import { intlLocale } from '$lib/util/locale';

export type Profile = 'hike' | 'alpine';
export type Run = Leg['details']['sac'][number];

/** Identifies a leg's inputs; equal keys can reuse a computed leg. */
export function legKey(
	from: { lon: number; lat: number },
	to: { lon: number; lat: number },
	straight: boolean,
	profile: Profile,
	through?: { lon: number; lat: number }
): string {
	const p = (x: number) => x.toFixed(6);
	const key = `${p(from.lon)},${p(from.lat)}>${p(to.lon)},${p(to.lat)}|${straight ? 'straight' : profile}`;
	return through && !straight ? `${key}|${p(through.lon)},${p(through.lat)}` : key;
}

/** The same leg walked the other way: no need to route it again. */
export function reverseLeg(leg: Leg): Leg {
	const last = leg.coordinates.length - 1;
	const flip = (runs: Run[]) =>
		runs.map((r) => ({ from: last - r.to, to: last - r.from, value: r.value })).reverse();
	return {
		...leg,
		coordinates: [...leg.coordinates].reverse(),
		ascent_m: leg.descent_m,
		descent_m: leg.ascent_m,
		duration_s: leg.duration_reverse_s,
		duration_reverse_s: leg.duration_s,
		details: {
			sac: flip(leg.details.sac),
			surface: flip(leg.details.surface),
			way_type: flip(leg.details.way_type),
			trail: flip(leg.details.trail)
		},
		snap: { from_m: leg.snap.to_m, to_m: leg.snap.from_m }
	};
}

export type Totals = {
	distanceM: number;
	ascentM: number;
	descentM: number;
	durationS: number;
	durationReverseS: number;
	eleMinM: number;
	eleMaxM: number;
	sacGrade: number;
	sacMax: number;
	sacBreakdown: Record<string, number>;
	unofficialM: number;
	surfaces: Record<string, number>;
	wayTypes: Record<string, number>;
	trails: Record<string, number>;
};

/** Route-wide numbers: sums of the legs, hardest SAC grade. */
export function totals(legs: Leg[]): Totals {
	const t: Totals = {
		distanceM: 0,
		ascentM: 0,
		descentM: 0,
		durationS: 0,
		durationReverseS: 0,
		eleMinM: Infinity,
		eleMaxM: -Infinity,
		sacGrade: 0,
		sacMax: 0,
		sacBreakdown: {},
		unofficialM: 0,
		surfaces: {},
		wayTypes: {},
		trails: {}
	};
	const add = (into: Record<string, number>, from: Record<string, number>) => {
		for (const [k, v] of Object.entries(from)) into[k] = (into[k] ?? 0) + v;
	};
	for (const l of legs) {
		t.distanceM += l.distance_m;
		t.ascentM += l.ascent_m;
		t.descentM += l.descent_m;
		t.durationS += l.duration_s;
		t.durationReverseS += l.duration_reverse_s;
		t.eleMinM = Math.min(t.eleMinM, l.ele_min_m);
		t.eleMaxM = Math.max(t.eleMaxM, l.ele_max_m);
		if (l.sac.grade > t.sacGrade) {
			t.sacGrade = l.sac.grade;
			t.sacMax = l.sac.max;
		} else if (l.sac.grade === t.sacGrade) {
			t.sacMax = Math.max(t.sacMax, l.sac.max);
		}
		add(t.sacBreakdown, l.sac.breakdown);
		t.unofficialM += l.sac.unofficial_m;
		add(t.surfaces, l.surfaces);
		add(t.wayTypes, l.way_types);
		add(t.trails, l.trails);
	}
	return t;
}

export type Profile3 = {
	/** [lon, lat, elevation] of the whole route, joints not repeated */
	coordinates: number[][];
	/** cumulative distance in metres per coordinate */
	distance: number[];
	/** SAC runs on the combined coordinate indices */
	sac: Run[];
};

/** The SAC grade at coordinate `i` («T3»), if the runs are grades. */
export function gradeAt(line: Profile3, i: number): string | undefined {
	const run = line.sac.find((r) => r.from <= i && i <= r.to);
	return run && /^T[1-6]$/.test(run.value) ? run.value : undefined;
}

/** Joins legs into one line with cumulative distances for the profile. */
export function combine(legs: Leg[]): Profile3 {
	const coordinates: number[][] = [];
	const distance: number[] = [];
	const sac: Run[] = [];
	for (const leg of legs) {
		const offset = coordinates.length === 0 ? 0 : coordinates.length - 1;
		const start = coordinates.length === 0 ? 0 : 1; // skip the shared joint
		for (let i = start; i < leg.coordinates.length; i++) {
			const c = leg.coordinates[i];
			const prev = coordinates[coordinates.length - 1];
			distance.push(prev ? distance[distance.length - 1] + haversine(prev, c) : 0);
			coordinates.push(c);
		}
		for (const r of leg.details.sac) {
			const last = sac[sac.length - 1];
			if (last && last.value === r.value && last.to === r.from + offset) last.to = r.to + offset;
			else sac.push({ from: r.from + offset, to: r.to + offset, value: r.value });
		}
	}
	return { coordinates, distance, sac };
}

function haversine(a: number[], b: number[]): number {
	const rad = Math.PI / 180;
	const dLat = (b[1] - a[1]) * rad;
	const dLon = (b[0] - a[0]) * rad;
	const h =
		Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * rad) * Math.cos(b[1] * rad) * Math.sin(dLon / 2) ** 2;
	return 2 * 6371008.8 * Math.asin(Math.sqrt(h));
}

/**
 * Hiking time as shown on Swiss signposts: rounded to 5 minutes, "3 h 25 min".
 * `factor` is the user's personal pace (1 = signpost pace).
 */
export function formatDuration(seconds: number, factor = 1): string {
	const minutes = Math.round((seconds * factor) / 60 / 5) * 5;
	const h = Math.floor(minutes / 60);
	const m = minutes % 60;
	if (h === 0) return `${m}${NBSP}min`;
	return m === 0 ? `${h}${NBSP}h` : `${h}${NBSP}h ${m}${NBSP}min`;
}

// Keeps a number and its unit on one line.
const NBSP = '\u00a0';

/** «19.3 km» in German, «19,3 km» in French; below a kilometre in metres. */
export function formatDistance(metres: number, locale = intlLocale()): string {
	if (metres < 1000) return formatHeight(metres);
	const km = new Intl.NumberFormat(locale, {
		minimumFractionDigits: 1,
		maximumFractionDigits: 1,
		useGrouping: false
	}).format(metres / 1000);
	return `${km}${NBSP}km`;
}

/** Heights, ascents and short distances in whole metres: «1707 m». */
export function formatHeight(metres: number): string {
	return `${Math.round(metres)}${NBSP}m`;
}

export function formatSAC(grade: number, max: number): string {
	if (grade === 0) return '–';
	return max > grade ? `T${grade}–T${max}` : `T${grade}`;
}
