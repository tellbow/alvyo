import { expect, test } from './fixtures';

// Tile x/y/z → longitude/latitude of the tile's north-west corner.
function tileLon(x: number, z: number) {
	return (x / 2 ** z) * 360 - 180;
}
function tileLat(y: number, z: number) {
	const n = Math.PI - (2 * Math.PI * y) / 2 ** z;
	return (180 / Math.PI) * Math.atan(Math.sinh(n));
}

test('swisstopo map with overlays that survive a base map switch', async ({ page }) => {
	const tiles: { z: number; x: number; y: number }[] = [];
	page.on('request', (req) => {
		const m = req.url().match(/\/tiles\/wmts\/[^/]+\/(\d+)\/(\d+)\/(\d+)\./);
		if (m) tiles.push({ z: +m[1], x: +m[2], y: +m[3] });
	});

	await page.goto('/plan');
	const map = page.getByTestId('map');
	await expect(map).toHaveAttribute('data-layers', /\bbase\b.*\bovl-wanderwege\b/);
	await expect(page.locator('.maplibregl-ctrl-attrib')).toContainText('© swisstopo');
	await expect(page.locator('.maplibregl-ctrl-attrib')).toBeVisible();
	const box = await page.locator('canvas.maplibregl-canvas').boundingBox();
	expect(box?.height ?? 0).toBeGreaterThan(300);
	await page.waitForLoadState('networkidle');
	await page.screenshot({ path: 'test-results/map-landeskarte.png' });

	// Switch to the vector base map: the hiking trail overlay stays on top.
	await page.getByRole('button', { name: 'Karten' }).click();
	await page.getByLabel('Basiskarte').check();
	await page.getByLabel('Relief').check();
	await expect(map).toHaveAttribute(
		'data-layers',
		/ovl-wanderwege.*ovl-relief|ovl-relief.*ovl-wanderwege/
	);
	await expect(map).not.toHaveAttribute('data-layers', /(^|\s)base(\s|$)/);
	await page.waitForLoadState('networkidle');
	await page.screenshot({ path: 'test-results/map-basemap.png' });

	// Every swisstopo tile we asked for intersects Switzerland/Liechtenstein.
	expect(tiles.length).toBeGreaterThan(0);
	for (const t of tiles) {
		const west = tileLon(t.x, t.z);
		const east = tileLon(t.x + 1, t.z);
		const north = tileLat(t.y, t.z);
		const south = tileLat(t.y + 1, t.z);
		expect(east > 5.7 && west < 10.8 && north > 45.6 && south < 48.0, JSON.stringify(t)).toBe(true);
	}

	// The choice is remembered.
	await page.reload();
	await expect(map).toHaveAttribute('data-layers', /ovl-relief/);
});

test('the terrain in 3D, from the tile cache, and flat again', async ({ page }) => {
	const terrain: string[] = [];
	page.on('response', (res) => {
		if (res.url().includes('/tiles/terrain/') && res.ok()) terrain.push(res.url());
	});
	await page.goto('/plan');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\bovl-wanderwege\b/);
	const on = page.getByRole('button', { name: 'Gelände in 3D zeigen' });
	await on.click();
	await expect(page.getByRole('button', { name: 'Gelände flach zeigen' })).toBeVisible();
	await expect.poll(() => terrain.length).toBeGreaterThan(0);
	expect(terrain.every((u) => new URL(u).origin === new URL(page.url()).origin)).toBe(true);
	await page.waitForLoadState('networkidle');
	await page.screenshot({ path: 'test-results/map-3d.png' });

	// A base map switch keeps it.
	await page.getByRole('button', { name: 'Karten' }).click();
	await page.getByLabel('Luftbild').check();
	await expect(page.getByRole('button', { name: 'Gelände flach zeigen' })).toBeVisible();
	// Without a GPU (CI), drawing the aerial pictures in 3D keeps the page
	// too busy for a click until they are loaded.
	await page.waitForLoadState('networkidle');
	await page.getByRole('button', { name: 'Gelände flach zeigen' }).click();
	await expect(on).toBeVisible();
});

test('the Landeskarte when swisstopo’s vector base map does not answer', async ({ page }) => {
	// The Basiskarte chosen before; its style, tiles and fonts fail.
	await page.addInitScript(() =>
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'basemap', overlays: ['wanderwege'], center: [8.2, 46.8], zoom: 9 })
		)
	);
	await page.route(/^https:\/\/vectortiles\d?\.geo\.admin\.ch\//, (r) =>
		r.fulfill({ status: 503, body: 'no available server' })
	);

	await page.goto('/plan');
	const map = page.getByTestId('map');
	await expect(map).toHaveAttribute('data-layers', /\bbase\b.*\bovl-wanderwege\b/);
	await expect(page.getByTestId('base-unavailable')).toContainText('Du siehst die Landeskarte');
	await page.getByRole('button', { name: 'Karten' }).click();
	await expect(page.getByLabel('Landeskarte', { exact: true })).toBeChecked();

	// Chosen again while it is still down: back to the Landeskarte.
	await page.getByRole('button', { name: 'Schliessen' }).click();
	await expect(page.getByTestId('base-unavailable')).toBeHidden();
	await page.getByRole('button', { name: 'Karten' }).click();
	await page.getByLabel('Basiskarte').check();
	await expect(page.getByTestId('base-unavailable')).toBeVisible();
	await expect(page.getByLabel('Landeskarte', { exact: true })).toBeChecked();
	await expect(map).toHaveAttribute('data-layers', /\bbase\b.*\bovl-wanderwege\b/);
});

test('the Landeskarte when the vector base map’s tiles keep failing', async ({ page }) => {
	// The style loads; its tile servers (vectortiles0–4) answer 503.
	await page.addInitScript(() =>
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'basemap', overlays: ['wanderwege'], center: [8.2, 46.8], zoom: 9 })
		)
	);
	await page.route(/^https:\/\/vectortiles\d\.geo\.admin\.ch\//, (r) =>
		r.fulfill({ status: 503, body: 'no available server' })
	);

	await page.goto('/plan');
	await expect(page.getByTestId('base-unavailable')).toBeVisible();
	await expect(page.getByTestId('map')).toHaveAttribute(
		'data-layers',
		/\bbase\b.*\bovl-wanderwege\b/
	);
});

test('summits and water on the map, with a popup', async ({ page }) => {
	// Zoomed in on the Reeti above Grindelwald First, the layer chosen before.
	await page.addInitScript(() =>
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege', 'pois'],
				center: [8.01154, 46.66494],
				zoom: 15
			})
		)
	);
	const pins = page.waitForResponse(
		(r) => r.url().includes('/places/in-view') && r.url().includes('kind=peak')
	);
	await page.goto('/plan');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\bovl-pois\b/);
	expect((await pins).ok()).toBe(true);
	const canvas = page.locator('canvas.maplibregl-canvas');
	await expect(canvas).toHaveCSS('cursor', /.*/);
	const box = (await canvas.boundingBox())!;
	// Once the icons are drawn.
	await expect(async () => {
		await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
		await expect(page.getByTestId('place-popup')).toContainText('Reeti', { timeout: 500 });
	}).toPass();
	await expect(page.getByTestId('place-popup')).toContainText(/Gipfel · 2757\sm/);
	await page.screenshot({ path: 'test-results/map-pois.png' });

	// Summits switched off: no longer asked for, and so on the next page.
	await page.keyboard.press('Escape');
	await page.getByRole('button', { name: 'Karten' }).click();
	const kinds = page.getByTestId('poi-kinds');
	await expect(kinds.getByRole('checkbox')).toHaveCount(10);
	const without = page.waitForResponse(
		(r) =>
			r.url().includes('/places/in-view') &&
			r.url().includes('kind=water') &&
			!r.url().includes('kind=peak')
	);
	await kinds.getByLabel('Gipfel').uncheck();
	await without;
	await page.goto('/discover');
	await page.getByRole('button', { name: 'Karten' }).click();
	await expect(page.getByTestId('poi-kinds').getByLabel('Gipfel')).not.toBeChecked();
	await expect(page.getByTestId('poi-kinds').getByLabel('Feuerstelle')).toBeChecked();
});

test('rain: the radar, then the forecast, on a timeline', async ({ page }) => {
	const at = (min: number) => new Date(Date.now() + min * 60_000).toISOString();
	const frame = (kind: string, time: string) => ({
		kind,
		time,
		url: `/api/v1/weather/precip/${kind}/${Date.parse(time) / 1000}/frame.png?v=1`
	});
	await page.route('**/api/v1/weather/precip', (r) =>
		r.fulfill({
			json: {
				bounds: { west: 2.689, south: 43.619, east: 12.462, north: 49.374 },
				frames: [frame('radar', at(-10)), frame('radar', at(-5)), frame('forecast', at(60))],
				legend: [
					{ from: 0.1, color: '#a6dbf7' },
					{ from: 40, color: '#96005a' }
				],
				attribution: 'MeteoSchweiz'
			}
		})
	);
	// A transparent pixel for every picture.
	await page.route('**/api/v1/weather/precip/*/*/frame.png*', (r) =>
		r.fulfill({
			contentType: 'image/png',
			body: Buffer.from(
				'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
				'base64'
			)
		})
	);

	await page.goto('/plan');
	const map = page.getByTestId('map');
	await expect(map).toHaveAttribute('data-layers', /\bovl-wanderwege\b/);
	await page.getByRole('button', { name: 'Karten' }).click();
	await page.getByLabel('Regen (Radar und Prognose)').check();
	await expect(map).toHaveAttribute('data-layers', /\bovl-precip\b/);
	const card = page.getByTestId('precip');
	// It starts at the newest radar picture.
	await expect(card.getByTestId('precip-kind')).toHaveText('Radar, gemessen');
	await expect(card.getByRole('slider')).toHaveValue('1');
	await card.getByRole('slider').press('ArrowRight');
	await expect(card.getByTestId('precip-kind')).toHaveText('Modellprognose');
	await expect(card.getByTestId('precip-time')).toHaveText(/\d\d:\d\d–\d\d:\d\d$/);
	await expect(card).toContainText('© MeteoSchweiz');

	// It stays with another base map, and goes when switched off.
	await page.getByLabel('Basiskarte').check();
	await expect(map).not.toHaveAttribute('data-layers', /(^|\s)base(\s|$)/);
	await expect(map).toHaveAttribute('data-layers', /\bovl-precip\b/);
	await page.getByLabel('Regen (Radar und Prognose)').uncheck();
	await expect(map).not.toHaveAttribute('data-layers', /\bovl-precip\b/);
	await expect(card).toHaveCount(0);
});
