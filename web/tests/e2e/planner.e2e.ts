import { expect, test } from './fixtures';

test('plan a route by clicking the map, then adjust it', async ({ page, context }) => {
	// Start zoomed in near Grindelwald First, where trails are dense.
	await context.addInitScript(() => {
		localStorage.setItem(
			'odysgeh.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 14
			})
		);
	});
	const id = `plan${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planner',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

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
	await page.screenshot({ path: 'test-results/planner.png' });

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
			'odysgeh.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `drag${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Dragger',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
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
			'odysgeh.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `path${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pathfinder',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
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
	const position = (x: number, y: number): LonLat => ({
		lon: 8.04 + (x - cx) * px,
		lat: 46.665 - (y - cy) * px * cos
	});

	await page.getByLabel('Anderer Weg').check();
	await page.mouse.click(cx - 200, cy);
	await page.mouse.click(cx + 200, cy);
	const legItems = page.getByTestId('leg');
	await expect(legItems.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	// The leg's JSON is read after the page may already show it.
	await expect.poll(() => legs.length).toBe(1);

	/** Presses the middle of the line and releases it 100 px further down. */
	const drag = async (alt: boolean) => {
		const line = legs.at(-1)!.coordinates;
		const mid = line[Math.floor(line.length / 2)];
		const from = screen(mid[0], mid[1]);
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
		await page.mouse.down();
		await page.mouse.move(from.x, from.y + 50, { steps: 4 });
		await page.mouse.move(from.x, from.y + 100, { steps: 4 });
		if (alt) await page.keyboard.down('Alt');
		await page.mouse.up();
		if (alt) await page.keyboard.up('Alt');
		return position(from.x, from.y + 100);
	};

	// The leg moves: the same two points, a leg request through the release
	// point, and the new line passes near it.
	const released = await drag(false);
	await expect.poll(() => requests.at(-1)?.through).toBeDefined();
	const through = requests.at(-1)!.through!;
	expect(Math.abs(through.lon - released.lon)).toBeLessThan(0.0005);
	expect(Math.abs(through.lat - released.lat)).toBeLessThan(0.0005);
	await expect(legItems.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await expect.poll(() => legs.length).toBe(2);
	await expect(page.getByTestId('anchor')).toHaveCount(2);
	await expect(page.getByTestId('through')).toHaveCount(1);
	const k = 111_000;
	const nearest = Math.min(
		...legs
			.at(-1)!
			.coordinates.map((c) => Math.hypot((c[0] - through.lon) * k * cos, (c[1] - through.lat) * k))
	);
	expect(nearest).toBeLessThan(150);

	// With Alt held, dragging adds a point as before.
	await drag(true);
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	await expect(page.getByTestId('through')).toHaveCount(0);
});

test('on a touch screen, hold the line to drag it; a quick swipe pans the map', async ({
	page,
	context
}) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'odysgeh.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [8.04, 46.665], zoom: 14 })
		);
	});
	const id = `touch${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Thumb',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

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
