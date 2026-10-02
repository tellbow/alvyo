/** A way between a leg's two points: [lon, lat] per point. */
export type Way = [number, number][];

/** Metres between two points close together (good enough for tens of metres). */
function metres(a: number[], b: number[]): number {
	const k = 111_320;
	const dx = (a[0] - b[0]) * k * Math.cos(((a[1] + b[1]) / 2) * (Math.PI / 180));
	return Math.hypot(dx, (a[1] - b[1]) * k);
}

/** Whether `way` is the one `line` takes: nearly all its points lie on it. */
export function sameWay(way: Way, line: number[][], withinM = 25): boolean {
	if (line.length === 0) return false;
	const step = Math.max(1, Math.floor(way.length / 40));
	let on = 0;
	let n = 0;
	for (let i = 0; i < way.length; i += step) {
		n++;
		if (line.some((c) => metres(way[i], c) <= withinM)) on++;
	}
	return on >= 0.9 * n;
}

/** The ways other than the one `line` (the leg as it is) takes, with their index among all. */
export function otherWays(ways: Way[], line: number[][]): { way: Way; index: number }[] {
	return ways.map((way, index) => ({ way, index })).filter(({ way }) => !sameWay(way, line));
}

/**
 * The way nearest to a screen position, with its point nearest to it and the
 * distance in pixels; `project` gives a [lon, lat] point's screen position.
 */
export function nearestWay<T extends { way: Way }>(
	ways: T[],
	at: { x: number; y: number },
	project: (p: [number, number]) => { x: number; y: number }
): { way: T; point: [number, number]; px: number } | undefined {
	let best: { way: T; point: [number, number]; px: number } | undefined;
	for (const w of ways) {
		for (const p of w.way) {
			const s = project(p);
			const px = Math.hypot(s.x - at.x, s.y - at.y);
			if (!best || px < best.px) best = { way: w, point: p, px };
		}
	}
	return best;
}

/**
 * The point of `way` farthest from the `others`: ways share stretches, and
 * the leg dragged there must take this way and not another one through the
 * same point.
 */
export function distinctPoint(way: Way, others: Way[]): [number, number] {
	let best = way[0];
	let bestM = -1;
	for (const p of way) {
		let m = Infinity;
		for (const o of others) for (const q of o) m = Math.min(m, metres(p, q));
		if (m > bestM) {
			best = p;
			bestM = m;
		}
	}
	return best;
}
