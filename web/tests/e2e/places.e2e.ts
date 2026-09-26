import { expect, test } from './fixtures';

test('huts overlay: a hut popup adds the hut to the planned route', async ({ page, context }) => {
	const hut = { lon: 9.27, lat: 47.03 };
	await context.addInitScript((c) => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({ base: 'landeskarte', overlays: [], center: [c.lon, c.lat], zoom: 12 })
		);
	}, hut);
	// The dev database need not hold huts: the answer is fixed.
	const asked: string[] = [];
	await page.route('**/api/v1/places/in-view?**', async (route) => {
		asked.push(route.request().url());
		await route.fulfill({
			json: {
				places: [
					{
						id: '0190a0b0-0000-7000-8000-000000000001',
						kind: 'hut',
						name: 'Spitzmeilenhütte SAC',
						detail: 'alpine_hut',
						website: 'https://www.spitzmeilen.ch',
						...hut
					}
				]
			}
		});
	});
	const id = `huts${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Huts',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	await page.goto('/plan');
	const map = page.getByTestId('map');
	const canvas = page.locator('canvas.maplibregl-canvas');
	await expect(canvas).toBeVisible();
	await page.getByRole('button', { name: 'Karten' }).click();
	await page.getByLabel('Hütten').check();
	await expect(map).toHaveAttribute('data-layers', /\bbase\b.*\bovl-huts\b/);
	await page.getByRole('button', { name: 'Karten' }).click(); // close the menu
	await expect.poll(() => asked.length).toBeGreaterThan(0);
	expect(new URL(asked[0]).searchParams.getAll('kind')).toEqual(['hut']);

	// The hut sits in the middle of the map: wait for the pointer over it.
	const box = (await canvas.boundingBox())!;
	const x = box.x + box.width / 2;
	const y = box.y + box.height / 2;
	await expect
		.poll(async () => {
			await page.mouse.move(x + 1, y);
			await page.mouse.move(x, y);
			return canvas.evaluate((c) => (c as HTMLElement).style.cursor);
		})
		.toBe('pointer');
	await page.mouse.click(x, y);

	const popup = page.getByTestId('place-popup');
	await expect(popup).toContainText('Spitzmeilenhütte SAC');
	await expect(popup).toContainText('Hütte');
	await expect(popup.getByRole('link', { name: /Website/ })).toHaveAttribute(
		'href',
		'https://www.spitzmeilen.ch/'
	);
	await page.screenshot({ path: 'test-results/places-popup.png' });
	// Clicking the hut opened its popup without adding a point.
	await expect(page.getByTestId('anchor')).toHaveCount(0);
	await popup.getByRole('button', { name: 'Als Routenpunkt hinzufügen' }).click();
	await expect(page.getByTestId('anchor')).toHaveCount(1);
	await expect(popup).toHaveCount(0);
});
