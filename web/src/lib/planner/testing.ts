import type { Leg } from '#lib/api/client.js';

/** A minimal leg straight from `from` to `to`, for tests. */
export function fakeLeg(coords: number[][], over: Partial<Leg> = {}): Leg {
	const n = coords.length - 1;
	return {
		coordinates: coords,
		distance_m: 1000,
		ascent_m: 100,
		descent_m: 20,
		ele_min_m: 500,
		ele_max_m: 600,
		duration_s: 1200,
		duration_reverse_s: 900,
		sac: { grade: 2, max: 3, breakdown: { T2: 1000 }, unofficial_m: 0 },
		surfaces: { gravel: 1000 },
		way_types: { path: 1000 },
		trails: { Bergwanderweg: 1000 },
		details: {
			sac: [{ from: 0, to: n, value: 'T2' }],
			surface: [{ from: 0, to: n, value: 'gravel' }],
			way_type: [{ from: 0, to: n, value: 'path' }],
			trail: [{ from: 0, to: n, value: 'Bergwanderweg' }]
		},
		snap: { from_m: 1, to_m: 2 },
		warnings: [],
		...over
	};
}
