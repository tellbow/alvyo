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
	await page.getByRole('button', { name: 'Gelände flach zeigen' }).click();
	await expect(on).toBeVisible();
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
	await page.waitForTimeout(500); // the dots are drawn
	await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
	await expect(page.getByTestId('place-popup')).toContainText('Reeti');
	await expect(page.getByTestId('place-popup')).toContainText(/Gipfel · 2757\sm/);
});
