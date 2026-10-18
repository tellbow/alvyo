import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('plan a route by clicking the map, then adjust it', async ({ page, context }) => {
	// Start zoomed in near Grindelwald First, where trails are dense.
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 14
			})
		);
	});
	const id = `plan${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planner',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);

	const legRequests: string[] = [];
	page.on('request', (r) => r.url().includes('/api/v1/routing/leg') && legRequests.push(r.url()));

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	await expect(canvas).toBeVisible();
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
	const box = (await canvas.boundingBox())!;
	const at = (dx: number, dy: number) => ({
		x: box.x + box.width / 2 + dx,
		y: box.y + box.height / 2 + dy
	});

	for (const p of [at(-250, 80), at(0, -60), at(250, 40)]) {
		await page.mouse.click(p.x, p.y);
	}
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	const legs = page.getByTestId('leg');
	await expect(legs).toHaveCount(2);
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	expect(legRequests).toHaveLength(2);

	await expect(page.getByTestId('stat-distance')).toContainText(/\d/);
	await expect(page.getByTestId('stat-time')).toContainText(/min|h/);
	await expect(page.getByTestId('stat-sac')).toContainText(/T\d/);
	await expect(page.getByTestId('elevation-profile')).toBeVisible();
	await expect(page.getByTestId('point').first()).toContainText(/\d+\sm/);
	await page.screenshot({ path: 'test-results/planner.png' });

	// The profile folds away and back; the browser remembers it.
	await page.getByTestId('profile-hide').click();
	await expect(page.getByTestId('elevation-profile')).toBeHidden();
	expect(await page.evaluate(() => localStorage.getItem('alvyo.profileFolded'))).toBe('1');
	await page.getByTestId('profile-show').click();
	await expect(page.getByTestId('elevation-profile')).toBeVisible();

	// Dragging the middle anchor recomputes exactly its two adjacent legs.
	const middle = (await page.getByTestId('anchor').nth(1).boundingBox())!;
	await page.mouse.move(middle.x + middle.width / 2, middle.y + middle.height / 2);
	await page.mouse.down();
	await page.mouse.move(middle.x + 60, middle.y + 90, { steps: 8 });
	await page.mouse.up();
	await expect.poll(() => legRequests.length).toBe(4);
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });

	// Undo restores the previous legs from the cache, without requests.
	await page.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok');
	await page.getByRole('button', { name: 'Umkehren' }).click();
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok');
	expect(legRequests).toHaveLength(4);

	// Clicks on a point are the point's own: one adds nothing, a double-click
	// removes it and adds nothing either.
	const anchors = page.getByTestId('anchor');
	await anchors.nth(1).click();
	await expect(anchors).toHaveCount(3);
	await anchors.nth(1).dblclick();
	await expect(anchors).toHaveCount(2);
});

/** A user logged in on /plan, zoomed in near Grindelwald First without overlays. */
async function planAt(
	page: import('@playwright/test').Page,
	context: import('@playwright/test').BrowserContext,
	name: string
) {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `${name}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: name,
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	const box = (await canvas.boundingBox())!;
	return { canvas, cx: box.x + box.width / 2, cy: box.y + box.height / 2 };
}

/** Where a position is on the screen at zoom 14 around [8.04, 46.665]. */
function screenAt(cx: number, cy: number) {
	// MapLibre's zoom 0 is 512 px wide: at zoom 14 a pixel is 360° / 2^23 of
	// longitude, and × cos(latitude) of latitude.
	const px = 360 / 2 ** 23;
	const cos = Math.cos((46.665 * Math.PI) / 180);
	return {
		px,
		cos,
		screen: (lon: number, lat: number) => ({
			x: cx + (lon - 8.04) / px,
			y: cy - (lat - 46.665) / (px * cos)
		})
	};
}

/** Drags the dot halfway along leg `i` to `to`, slowly enough for the ways to come. */
async function dragDot(page: import('@playwright/test').Page, to: { x: number; y: number }, i = 0) {
	const dot = (await page.getByTestId('midpoint').nth(i).boundingBox())!;
	const from = { x: dot.x + dot.width / 2, y: dot.y + dot.height / 2 };
	await page.mouse.move(from.x, from.y);
	await page.mouse.down();
	await page.mouse.move((from.x + to.x) / 2, (from.y + to.y) / 2, { steps: 4 });
	await page.mouse.move(to.x, to.y, { steps: 4 });
	await page.waitForTimeout(300); // the ways arrive while dragging
	await page.mouse.move(to.x + 1, to.y);
	await page.mouse.move(to.x, to.y);
	await page.mouse.up();
}

test("a leg's dot let go off every way: a stop there", async ({ page, context }) => {
	type LegBody = { to: { lon: number; lat: number } };
	const legRequests: LegBody[] = [];
	page.on('request', (r) => {
		if (r.url().includes('/api/v1/routing/leg')) legRequests.push(r.postDataJSON());
	});
	const { cx, cy } = await planAt(page, context, 'dot');
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legs = page.getByTestId('leg');
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// A straight line has no other ways: a stop wherever the dot goes.
	await legs.nth(0).getByLabel('Gerade Linie').check();
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await expect(page.getByTestId('midpoint')).toHaveCount(1);
	const before = legRequests.length;

	await dragDot(page, { x: cx + 40, y: cy + 120 });
	await page.screenshot({ path: 'test-results/drag.png' });

	// One new point where it was let go; only its two legs are computed.
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	await expect(legs).toHaveCount(2);
	await expect.poll(() => legRequests.length).toBe(before + 2);
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	const { px, cos } = screenAt(cx, cy);
	const released = { lon: 8.04 + 40 * px, lat: 46.665 - 120 * px * cos };
	const to = legRequests[before].to;
	expect(Math.abs(to.lon - released.lon)).toBeLessThan(0.0005);
	expect(Math.abs(to.lat - released.lat)).toBeLessThan(0.0005);
	// Each leg has its dot again.
	await expect(page.getByTestId('midpoint')).toHaveCount(2);

	// The map did not pan while dragging: the start marker stayed.
	const start = (await page.getByTestId('anchor').nth(0).boundingBox())!;
	expect(Math.abs(start.x + start.width / 2 - (cx - 200))).toBeLessThan(40);
});

test("a leg's dot let go on another way: the leg takes it", async ({ page, context }) => {
	type LonLat = { lon: number; lat: number };
	const requests: { through?: LonLat }[] = [];
	const legs: { coordinates: number[][] }[] = [];
	page.on('request', (r) => {
		if (r.url().includes('/api/v1/routing/leg')) requests.push(r.postDataJSON());
	});
	page.on('response', (r) => {
		// Answers still arriving when the test ends are not needed.
		if (r.url().includes('/api/v1/routing/leg') && r.ok())
			r.json().then(
				(leg) => legs.push(leg),
				() => {}
			);
	});
	const { cx, cy } = await planAt(page, context, 'path');
	const { screen } = screenAt(cx, cy);
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legItems = page.getByTestId('leg');
	await expect(legItems.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// The leg's JSON is read after the page may already show it.
	await expect.poll(() => legs.length).toBe(1);

	// The ways between the two points, as the API offers them: the leg's own
	// and one bulging 300 m south through where the dot will be let go.
	const own = legs[0].coordinates.map((c) => [c[0], c[1]]);
	const mid = own[Math.floor(own.length / 2)];
	const south = own.map(([lon, lat]) => {
		const t = Math.max(0, 1 - Math.abs(lon - mid[0]) / 0.004);
		return [lon, lat - (300 / 111_000) * t];
	});
	let ways = [own, south];
	let asked = 0;
	await page.route('**/api/v1/routing/alternatives', (route) => {
		asked++;
		return route.fulfill({ json: { ways } });
	});
	const anchors = page.getByTestId('anchor');
	const southScreen = screen(mid[0], mid[1] - 300 / 111_000);

	// On the southern way: the leg takes it, through a point on it (where it
	// is farthest from the leg's own), and no point is added.
	const before = requests.length;
	await dragDot(page, southScreen);
	await expect.poll(() => requests.length).toBeGreaterThan(before);
	const through = requests.at(-1)!.through!;
	expect(south.some((p) => p[0] === through.lon && p[1] === through.lat)).toBe(true);
	expect(asked).toBe(1);
	await expect(legItems.nth(0)).toHaveAttribute('data-state', /ok|error/, { timeout: 15_000 });
	await expect(anchors).toHaveCount(2);
	await expect(page.getByTestId('through')).toHaveCount(1);

	// Away from every way: a stop there.
	await page.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(page.getByTestId('through')).toHaveCount(0);
	await expect(page.getByTestId('midpoint')).toHaveCount(1);
	const dot = (await page.getByTestId('midpoint').boundingBox())!;
	await dragDot(page, { x: dot.x, y: dot.y - 150 });
	await expect(anchors).toHaveCount(3);
	await expect(page.getByTestId('through')).toHaveCount(0);

	// No other way at all: a stop as well, also on the southern way.
	await page.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(anchors).toHaveCount(2);
	ways = [own];
	await dragDot(page, southScreen);
	await expect(anchors).toHaveCount(3);

	// A click on the line adds a destination, as anywhere on the map.
	await expect(legItems.nth(1)).toHaveAttribute('data-state', /ok|error/, { timeout: 15_000 });
	await page.mouse.click(screen(mid[0], mid[1]).x, screen(mid[0], mid[1]).y);
	await expect(anchors).toHaveCount(4);
});

test('on a touch screen the dot moves with the finger; a swipe beside it pans', async ({
	page,
	context
}) => {
	const { cx, cy } = await planAt(page, context, 'touch');
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legs = page.getByTestId('leg');
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await legs.nth(0).getByLabel('Gerade Linie').check();
	await expect(page.getByTestId('midpoint')).toHaveCount(1);

	// Touch events as a phone sends them (Playwright itself only taps).
	const cdp = await context.newCDPSession(page);
	const touch = (type: 'touchStart' | 'touchMove' | 'touchEnd', x?: number, y?: number) =>
		cdp.send('Input.dispatchTouchEvent', {
			type,
			touchPoints: x === undefined ? [] : [{ x, y: y! }]
		});
	const swipe = async (x: number, y: number) => {
		await touch('touchStart', x, y);
		for (let i = 1; i <= 6; i++) await touch('touchMove', x + i * 7, y + i * 20);
		await touch('touchEnd');
	};
	const start = async () => (await page.getByTestId('anchor').nth(0).boundingBox())!.x;

	// The dot under the finger: a new point, no panning.
	const dot = (await page.getByTestId('midpoint').boundingBox())!;
	const before = await start();
	await swipe(dot.x + dot.width / 2, dot.y + dot.height / 2);
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	expect(Math.abs((await start()) - before)).toBeLessThan(2);

	// Beside it the map pans and the points stay.
	await page.waitForTimeout(500);
	await swipe(cx, cy - 150);
	await expect.poll(start).not.toBeCloseTo(before, 0);
	await expect(page.getByTestId('anchor')).toHaveCount(3);
});

test('planning needs an account', async ({ page }) => {
	await page.goto('/plan');
	await expect(page.getByTestId('planner-panel')).toContainText('Melde dich an');
});

test('a saved route opens in the planner zoomed to it', async ({ page, context }) => {
	// The last view far away, in Lausanne.
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [6.63, 46.52], zoom: 13 })
		);
	});
	const id = `open${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Opener',
			password: 'sehr-geheim-123'
		}
	});
	const created = await page.request.post('/api/v1/routes', {
		data: { title: 'Am Brienzersee', ...routeContent(8.04, 46.665, 20) }
	});
	const route = (await created.json()).id as string;

	await page.goto(`/plan/${route}`);
	const map = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
	const anchors = page.getByTestId('anchor');
	await expect(anchors).toHaveCount(2);
	for (const a of await anchors.all()) {
		const b = (await a.boundingBox())!;
		expect(b.x).toBeGreaterThan(map.x);
		expect(b.x + b.width).toBeLessThan(map.x + map.width);
		expect(b.y).toBeGreaterThan(map.y);
		expect(b.y + b.height).toBeLessThan(map.y + map.height);
	}
});
