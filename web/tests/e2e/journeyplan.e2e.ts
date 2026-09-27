import { expect, test } from './fixtures';

test('plan a three-day hike, pick another night, create the journey', async ({ page, context }) => {
	// Gaflei and Elm both in view (zoom 10, centred between them).
	const center = { lon: 9.3567, lat: 47.0317 };
	await context.addInitScript((c) => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [c.lon, c.lat], zoom: 10 })
		);
	}, center);
	const id = `jplan${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Via Alpina',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	await page.goto('/journeys');
	await page.getByRole('link', { name: 'Etappentour planen' }).click();
	await expect(page).toHaveURL(/\/journeys\/plan$/);
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /route-collection-line/);

	// A position on the screen: at zoom 10 a pixel is 360° / 2^19 of
	// longitude, and × cos(latitude) of latitude.
	const box = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
	const px = 360 / 2 ** 19;
	const click = (lon: number, lat: number) =>
		page.mouse.click(
			box.x + box.width / 2 + (lon - center.lon) / px,
			box.y + box.height / 2 - (lat - center.lat) / (px * Math.cos((center.lat * Math.PI) / 180))
		);
	await click(9.5428, 47.14472); // Gaflei
	await click(9.1706, 46.9186); // Elm
	await expect(page.getByTestId('plan-point')).toHaveCount(2);

	const panel = page.getByTestId('journey-plan-panel');
	await panel.getByLabel('Tage', { exact: true }).fill('3');
	await panel.getByRole('button', { name: 'Etappen vorschlagen' }).click();
	const stages = page.getByTestId('plan-stage');
	await expect(stages).toHaveCount(3, { timeout: 30_000 });
	await expect(stages.nth(2).getByTestId('plan-stage-end')).toContainText('bis zum Ziel');

	// Another night for the first day; the plan follows.
	const later = stages.first().getByRole('button', { name: /^Später: / });
	const place = (await later.textContent())!.replace(/^Später: /, '').trim();
	await later.click();
	await expect(stages.first().getByTestId('plan-stage-end')).toContainText(place, {
		timeout: 30_000
	});

	await panel.getByLabel('Titel').fill('Via Alpina, Gaflei – Elm');
	await panel.getByRole('button', { name: 'Etappentour erstellen' }).click();
	await expect(page.getByTestId('journey-title')).toHaveText('Via Alpina, Gaflei – Elm');
	await expect(page.getByTestId('stage')).toHaveCount(3);
	await expect(page.getByTestId('stage').first().getByTestId('stage-end')).toContainText(place);
	await expect(page.getByTestId('gap')).toHaveCount(0); // each day starts where the last ended
});

test('a point added while planning drops the plan for the old points', async ({ page }) => {
	const id = `jstale${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Eilig',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	// The plan's answer is held back until the third point is placed.
	let release = () => {};
	const held = new Promise<void>((r) => (release = r));
	await page.route('**/api/v1/journeys/plan', async (route) => {
		await held;
		await route.continue();
	});

	await page.goto('/journeys/plan');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /route-collection-line/);
	const box = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
	const click = (dx: number) =>
		page.mouse.click(box.x + box.width / 2 + dx, box.y + box.height / 2);
	await click(-100);
	await click(100);
	const panel = page.getByTestId('journey-plan-panel');
	await panel.getByRole('button', { name: 'Etappen vorschlagen' }).click();
	await click(200);
	await expect(page.getByTestId('plan-point')).toHaveCount(3);

	const answered = page.waitForResponse('**/api/v1/journeys/plan');
	release();
	await answered;
	await page.evaluate(() => new Promise(requestAnimationFrame));
	// Neither stages nor a problem of the plan for two points.
	await expect(page.getByTestId('plan-stage')).toHaveCount(0);
	await expect(panel.getByRole('alert')).toHaveCount(0);
	await expect(panel.getByRole('button', { name: 'Etappen vorschlagen' })).toBeEnabled();
});

test('the planners are one switch apart', async ({ page }) => {
	const id = `tabs${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planerin',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	await page.goto('/plan');
	const tabs = page.getByTestId('plan-tabs');
	await expect(tabs.getByRole('link', { name: 'Route' })).toHaveAttribute('aria-current', 'page');
	await tabs.getByRole('link', { name: 'Etappentour' }).click();
	await expect(page).toHaveURL(/\/journeys\/plan$/);
	await expect(page.getByTestId('journey-plan-panel')).toBeVisible();
	await page.getByTestId('plan-tabs').getByRole('link', { name: 'Route' }).click();
	await expect(page).toHaveURL(/\/plan$/);
});
