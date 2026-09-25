/**
 * An SVG path of a hike's lines ([lon, lat] points), fitted into a w × h box
 * with the same scale both ways, as a thumbnail of its shape.
 */
export function outline(lines: number[][][], w: number, h: number, pad = 2): string {
	const pts = lines.flat();
	if (pts.length < 2) return '';
	// Degrees of longitude are shorter than those of latitude up here.
	const k = Math.cos((pts[0][1] * Math.PI) / 180);
	const xs = pts.map((p) => p[0] * k);
	const ys = pts.map((p) => p[1]);
	const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
	// A line straight north or east has no extent the other way to fit.
	const fit = (room: number, span: number) => (span ? room / span : Infinity);
	const s = Math.min(fit(w - 2 * pad, x1 - x0), fit(h - 2 * pad, y1 - y0));
	if (!Number.isFinite(s)) return '';
	const ox = (w - (x1 - x0) * s) / 2;
	const oy = (h - (y1 - y0) * s) / 2;
	const f = (v: number) => Math.round(v * 10) / 10;
	return lines
		.map((line) =>
			line
				.map(
					(p, i) => `${i ? 'L' : 'M'}${f(ox + (p[0] * k - x0) * s)} ${f(h - oy - (p[1] - y0) * s)}`
				)
				.join('')
		)
		.join('');
}
