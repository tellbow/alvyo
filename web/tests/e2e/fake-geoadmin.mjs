// geo.admin's profile and identify services for end-to-end tests, so that an
// outage there does not stop a release. Started by playwright.config.ts; the
// real services are checked by
// `go test -tags live ./swiss/elevation/ ./api/internal/areas/`.
//
// Heights are made up: smooth hills over Switzerland. Areas are geo.admin's
// answer for the line of areas.e2e.ts (files/identify-grindelwald.json,
// recorded 2026-10-25; © BAFU, geo.admin.ch), given for lines near them.
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';

const PORT = 18091;
const features = JSON.parse(
	readFileSync(new URL('./files/identify-grindelwald.json', import.meta.url), 'utf8')
);

/** A height in metres at LV95 (east, north): between 400 and 2400 m. */
const height = (e, n) => 1400 + 600 * Math.sin(e / 4000) + 400 * Math.cos(n / 3000);

/** West, south, east and north of all [lon, lat] pairs in nested arrays. */
function bounds(coords) {
	const box = [Infinity, Infinity, -Infinity, -Infinity];
	const walk = (c) => {
		if (typeof c[0] === 'number') {
			box[0] = Math.min(box[0], c[0]);
			box[1] = Math.min(box[1], c[1]);
			box[2] = Math.max(box[2], c[0]);
			box[3] = Math.max(box[3], c[1]);
		} else c.forEach(walk);
	};
	walk(coords);
	return box;
}
const overlap = (a, b) => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];

createServer(async (req, res) => {
	const url = new URL(req.url, `http://localhost:${PORT}`);
	const json = (v) => {
		res.writeHead(200, { 'content-type': 'application/json' });
		res.end(JSON.stringify(v));
	};
	if (url.pathname === '/rest/services/profile.json') {
		let s = '';
		for await (const chunk of req) s += chunk;
		let dist = 0;
		return json(
			JSON.parse(s).coordinates.map(([e, n], i, all) => {
				if (i > 0) dist += Math.hypot(e - all[i - 1][0], n - all[i - 1][1]);
				const h = Math.round(height(e, n) * 10) / 10;
				return { dist, alts: { COMB: h, DTM2: h, DTM25: h }, easting: e, northing: n };
			})
		);
	}
	if (url.pathname === '/rest/services/api/MapServer/identify') {
		const layers = (url.searchParams.get('layers') ?? '').replace(/^all:/, '').split(',');
		const line = bounds(JSON.parse(url.searchParams.get('geometry')).paths);
		return json({
			results: features.filter(
				(f) => layers.includes(f.layerBodId) && overlap(bounds(f.geometry.coordinates), line)
			)
		});
	}
	res.writeHead(404).end();
}).listen(PORT, () => console.log(`fake geo.admin on ${PORT}`));
