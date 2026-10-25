// What the Apple Watch pictures show (watch.sh): seed.sh's account's tours
// and a hike on the «Eiger Trail» a third of the way along, as the iPhone's
// navigation picture, in the form the phone sends it to the watch
// (lib/navigation/watch.dart). Needs the web dev server and seed.sh's account.
// Usage: bun app/store/watch-state.mjs > state.json
const web = 'http://localhost:5173';

const login = await fetch(`${web}/api/v1/auth/login`, {
	method: 'POST',
	headers: { Origin: web, 'Content-Type': 'application/json' },
	body: JSON.stringify({ login: 'storeshots', password: 'store-shots-2026' })
});
if (!login.ok) throw new Error(`login: ${login.status} (run seed.sh first)`);
const cookie = login.headers
	.getSetCookie()
	.map((c) => c.split(';')[0])
	.join('; ');
const get = async (path) => {
	const r = await fetch(`${web}/api/v1${path}`, { headers: { Cookie: cookie } });
	if (!r.ok) throw new Error(`${path}: ${r.status}`);
	return r.json();
};

// As the phone's list: one's routes not hiked yet.
const { routes } = await get('/routes');
const tours = routes
	.filter((r) => !r.done_on)
	.map((r) => ({ id: r.id, title: r.title, distanceM: r.totals.distance_m, durationS: r.totals.duration_s }));
// The hike's tour first, as one would pick it.
tours.sort((a, b) => (b.title === 'Eiger Trail') - (a.title === 'Eiger Trail'));

const summary = routes.find((r) => r.title === 'Eiger Trail');
const route = await get(`/routes/${summary.id}`);
const { turns } = await get(`/routes/${summary.id}/turns`);
const line = route.legs.flatMap((l) => l.coordinates);

// Metres along the line, as the app's tracker counts them.
const along = [0];
for (let i = 1; i < line.length; i++) {
	const [a, b] = [line[i - 1], line[i]];
	const dx = (b[0] - a[0]) * Math.cos((((a[1] + b[1]) / 2) * Math.PI) / 180) * 111320;
	const dy = (b[1] - a[1]) * 111320;
	along.push(along[i - 1] + Math.hypot(dx, dy));
}
const cut = Math.round(line.length * 0.35);
const doneM = along[cut];
const lengthM = along.at(-1);
let up = 0;
for (let i = cut + 1; i < line.length; i++) up += Math.max(0, line[i][2] - line[i - 1][2]);
const next = turns.find((t) => t.along_m > doneM);
// At most 300 points, as the phone sends.
const step = Math.ceil(line.length / 300);
const shown = line.filter((_, i) => i % step === 0 || i === line.length - 1);

const share = 1 - doneM / lengthM;
console.log(
	JSON.stringify({
		tours,
		hike: {
			title: route.title,
			routeId: route.id,
			paused: false,
			elapsedS: Math.round(route.totals.duration_s * (1 - share)),
			line: shown.flatMap((p) => [p[0], p[1]]),
			position: [line[cut][0], line[cut][1]],
			doneM,
			remainingM: lengthM - doneM,
			remainingS: Math.round(route.totals.duration_s * share),
			ascentRemainingM: Math.min(up, route.totals.ascent_m),
			offRoute: false,
			offRouteM: 0,
			arrived: false,
			...(next && { turn: next.kind, turnInM: next.along_m - doneM })
		}
	})
);
