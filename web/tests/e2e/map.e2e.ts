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
