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

test('drag the line to a different path', async ({ page, context }) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `drag${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Dragger',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	type LegBody = { to: { lon: number; lat: number } };
	const legRequests: LegBody[] = [];
	page.on('request', (r) => {
		if (r.url().includes('/api/v1/routing/leg')) legRequests.push(r.postDataJSON());
	});

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	const box = (await canvas.boundingBox())!;
	const cx = box.x + box.width / 2;
	const cy = box.y + box.height / 2;
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legs = page.getByTestId('leg');
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// As a straight line the leg certainly runs through the middle.
	await legs.nth(0).getByLabel('Gerade Linie').check();
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	const before = legRequests.length;

	// Pressed only once the line is drawn there (the pointer shows it), or
	// the press would pan the map.
	await expect
		.poll(
			async () => {
				await page.mouse.move(cx + 1, cy);
				await page.mouse.move(cx, cy);
				return canvas.evaluate((c) => (c as HTMLCanvasElement).style.cursor);
			},
			{ timeout: 10_000 }
		)
		.toBe('pointer');
	await page.mouse.down();
	await page.mouse.move(cx + 20, cy + 60, { steps: 4 });
	await page.mouse.move(cx + 40, cy + 120, { steps: 4 });
	await page.screenshot({ path: 'test-results/drag.png' });
	await page.mouse.up();

	// One new point where it was released; only its two legs are computed.
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	await expect(legs).toHaveCount(2);
	await expect.poll(() => legRequests.length).toBe(before + 2);
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// MapLibre's zoom 0 is 512 px wide: at zoom 14 a pixel is 360° / 2^23 of
	// longitude, and × cos(latitude) of latitude. Released 40 px right and
	// 120 px down of the centre.
	const px = 360 / 2 ** 23;
	const released = {
		lon: 8.04 + 40 * px,
		lat: 46.665 - 120 * px * Math.cos((46.665 * Math.PI) / 180)
	};
	const to = legRequests[before].to;
	expect(Math.abs(to.lon - released.lon)).toBeLessThan(0.0005);
	expect(Math.abs(to.lat - released.lat)).toBeLessThan(0.0005);

	// The map did not pan while dragging: the start marker stayed.
	const start = (await page.getByTestId('anchor').nth(0).boundingBox())!;
	expect(Math.abs(start.x + start.width / 2 - (cx - 200))).toBeLessThan(40);
});

test('drag the line onto another path without a new point', async ({ page, context }) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `path${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pathfinder',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
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

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	const box = (await canvas.boundingBox())!;
	const cx = box.x + box.width / 2;
	const cy = box.y + box.height / 2;
	// Where a position is on the screen (see the test above for the scale).
	const px = 360 / 2 ** 23;
	const cos = Math.cos((46.665 * Math.PI) / 180);
	const screen = (lon: number, lat: number) => ({
		x: cx + (lon - 8.04) / px,
		y: cy - (lat - 46.665) / (px * cos)
	});

	await page.getByLabel('Anderer Weg').check();
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legItems = page.getByTestId('leg');
	await expect(legItems.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// The leg's JSON is read after the page may already show it.
	await expect.poll(() => legs.length).toBe(1);

	/** Presses the line at `from` and lets it go at `to` (Alt held if `alt`). */
	const dragTo = async (
		from: { x: number; y: number },
		to: { x: number; y: number },
		alt = false
	) => {
		await expect
			.poll(
				async () => {
					await page.mouse.move(from.x + 1, from.y);
					await page.mouse.move(from.x, from.y);
					return canvas.evaluate((c) => (c as HTMLCanvasElement).style.cursor);
				},
				{ timeout: 10_000 }
			)
			.toBe('pointer');
		if (alt) await page.keyboard.down('Alt');
		await page.mouse.down();
		await page.mouse.move((from.x + to.x) / 2, (from.y + to.y) / 2, { steps: 4 });
		await page.mouse.move(to.x, to.y, { steps: 4 });
		await page.waitForTimeout(300); // the ways arrive while dragging
		await page.mouse.up();
		if (alt) await page.keyboard.up('Alt');
	};

	// The ways between the two points, as the API offers them: the leg's own
	// and one bulging 300 m south through where the line will be let go.
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
	const notice = page.getByTestId('map-notice');

	// Let go on the southern way: the leg takes it, through a point on it
	// (where it is farthest from the leg's own), and no point is added.
	const before = requests.length;
	const southScreen = screen(mid[0], mid[1] - 300 / 111_000);
	const line = legs.at(-1)!.coordinates;
	const from = screen(line[Math.floor(line.length / 2)][0], line[Math.floor(line.length / 2)][1]);
	await dragTo(from, southScreen);
	await expect.poll(() => requests.length).toBeGreaterThan(before);
	const through = requests.at(-1)!.through!;
	expect(south.some((p) => p[0] === through.lon && p[1] === through.lat)).toBe(true);
	expect(asked).toBe(1);
	await expect(legItems.nth(0)).toHaveAttribute('data-state', /ok|error/, { timeout: 15_000 });
	await expect(page.getByTestId('anchor')).toHaveCount(2);
	await expect(page.getByTestId('through')).toHaveCount(1);
	await expect(notice).toHaveCount(0);

	// Let go away from every way: nothing changes, the user is told.
	const legsAsked = requests.length;
	await page.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(page.getByTestId('through')).toHaveCount(0);
	const undone = requests.length;
	await dragTo(from, { x: from.x, y: from.y - 150 });
	await expect(notice).toHaveText('Lass die Linie auf einem der hervorgehobenen Wege los.');
	expect(requests.length).toBe(undone);
	expect(legsAsked).toBeGreaterThan(0);

	// No other way at all: said so.
	ways = [own];
	await dragTo(from, southScreen);
	await expect(notice).toHaveText('Zwischen diesen Punkten gibt es keinen anderen Weg.');
	await expect(page.getByTestId('anchor')).toHaveCount(2);

	// A click on the line adds no point here.
	await page.mouse.click(from.x, from.y);
	await expect(notice).toHaveText(
		'Zieh die Linie: andere Wege erscheinen, auf einem lässt du sie los.'
	);
	await expect(page.getByTestId('anchor')).toHaveCount(2);

	// With Alt held, dragging adds a point as before.
	await dragTo(from, { x: from.x, y: from.y + 100 }, true);
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	await expect(page.getByTestId('through')).toHaveCount(0);
});

test('on a touch screen, hold the line to drag it; a quick swipe pans the map', async ({
	page,
	context
}) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `touch${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Thumb',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	const box = (await canvas.boundingBox())!;
	const cx = box.x + box.width / 2;
	const cy = box.y + box.height / 2;
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legs = page.getByTestId('leg');
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// A straight line certainly runs through the middle.
	await legs.nth(0).getByLabel('Gerade Linie').check();
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await expect
		.poll(
			async () => {
				await page.mouse.move(cx + 1, cy);
				await page.mouse.move(cx, cy);
				return canvas.evaluate((c) => (c as HTMLCanvasElement).style.cursor);
			},
			{ timeout: 10_000 }
		)
		.toBe('pointer');

	// Touch events as a phone sends them (Playwright itself only taps).
	const cdp = await context.newCDPSession(page);
	const touch = (type: 'touchStart' | 'touchMove' | 'touchEnd', x?: number, y?: number) =>
		cdp.send('Input.dispatchTouchEvent', {
			type,
			touchPoints: x === undefined ? [] : [{ x, y: y! }]
		});
	const swipe = async (hold: number) => {
		await touch('touchStart', cx, cy);
		await page.waitForTimeout(hold);
		for (let i = 1; i <= 6; i++) await touch('touchMove', cx + i * 7, cy + i * 20);
		await touch('touchEnd');
	};
	const start = async () => (await page.getByTestId('anchor').nth(0).boundingBox())!.x;

	// Held still first, the finger takes the line: a new point, no panning.
	const before = await start();
	await swipe(700);
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	expect(Math.abs((await start()) - before)).toBeLessThan(2);

	// A quick swipe pans the map and leaves the points alone.
	await page.waitForTimeout(500);
	await swipe(0);
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
