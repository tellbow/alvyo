/** A synthetic planner leg along the given points; the API recomputes the numbers. */
export function leg(coords: number[][]) {
	const run = (value: string) => [{ from: 0, to: coords.length - 1, value }];
	return {
		coordinates: coords,
		distance_m: 0,
		ascent_m: 0,
		descent_m: 0,
		ele_min_m: 0,
		ele_max_m: 0,
		duration_s: 0,
		duration_reverse_s: 0,
		sac: { grade: 0, max: 3, breakdown: {}, unofficial_m: 0 },
		surfaces: {},
		way_types: {},
		trails: {},
		details: {
			sac: run('T2'),
			surface: run('gravel'),
			way_type: run('path'),
			trail: run('Wanderweg')
		},
		snap: { from_m: 0, to_m: 0 },
		warnings: []
	};
}

/** A straight route body from (lon0, lat) eastwards by `steps` × 0.0005°. */
export function routeContent(lon0: number, lat: number, steps = 4) {
	const coords = Array.from({ length: steps + 1 }, (_, i) => [
		lon0 + i * 0.0005,
		lat,
		1000 + i * 5
	]);
	return {
		profile: 'hike',
		anchors: [
			{ lon: coords[0][0], lat },
			{ lon: coords[steps][0], lat }
		],
		legs: [leg(coords)]
	};
}
