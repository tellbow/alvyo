import { expect, test } from './fixtures';
import { routeContent } from './legs';

test.use({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });

test('on a phone no page is wider than the screen, and the menu leads on', async ({ page }) => {
	const id = `phone${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Phone',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const res = await page.request.post('/api/v1/routes', {
		data: { title: `Handyweg ${id}`, visibility: 'private', ...routeContent(8.3, 46.9) }
	});
	const route = (await res.json()).id;

	const wide = () => page.evaluate(() => document.documentElement.scrollWidth);
	for (const path of [
		'/',
		'/discover',
		'/plan',
		'/routes',
		'/journeys',
		'/account',
		`/routes/${route}`
	]) {
		await page.goto(path);
		await expect(page.getByTestId('menu')).toBeEnabled();
		expect(await wide(), path).toBeLessThanOrEqual(390);
	}

	// Not even while a route loads (the elevation profile before it measured
	// its width): the widest of every frame.
	await page.addInitScript(() => {
		const w = window as unknown as { widest: number };
		w.widest = 0;
		const frame = () => {
			w.widest = Math.max(w.widest, document.documentElement?.scrollWidth ?? 0);
			requestAnimationFrame(frame);
		};
		requestAnimationFrame(frame);
	});
	await page.goto(`/routes/${route}`);
	await expect(page.getByTestId('route-stats')).toBeVisible();
	await page.waitForTimeout(1000);
	expect(
		await page.evaluate(() => (window as unknown as { widest: number }).widest)
	).toBeLessThanOrEqual(390);

	// The map above, the panel below.
	const map = (await page.getByTestId('map').boundingBox())!;
	expect(map.width).toBeGreaterThan(380);

	// Fields of at least 16 px: Safari zooms into smaller ones.
	await page.goto('/plan');
	const search = page.getByLabel('Start suchen');
	await expect(search).toBeVisible();
	expect(
		await search.evaluate((e) => parseFloat(getComputedStyle(e).fontSize))
	).toBeGreaterThanOrEqual(16);

	await page.getByTestId('menu').click();
	await page.getByRole('link', { name: 'Meine Routen' }).click();
	await expect(page).toHaveURL(/\/routes$/);
	await expect(page.locator('#menu')).toHaveCount(0);
	await expect(page.getByTestId('route-list')).toContainText(`Handyweg ${id}`);
});
