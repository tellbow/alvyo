import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('the map of my hikes filters by tag and distance', async ({ page }) => {
	const id = `map${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Mapper',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	// About 150 m and 750 m long.
	for (const [title, lon, steps, tags] of [
		['Kurz', 8.04, 4, ['Winter']],
		['Lang', 8.05, 20, ['winter', 'Tessin']],
		['Ohne', 8.06, 20, []]
	] as const) {
		const res = await page.request.post('/api/v1/routes', {
			data: { title, tags, ...routeContent(lon, 46.665, steps) }
		});
		expect(res.status()).toBe(201);
	}

	await page.goto('/routes');
	await page.getByRole('link', { name: 'Karte', exact: true }).click();
	await expect(page).toHaveURL(/\/routes\/map/);
	await page.goto('/routes/map?bbox=8.03,46.66,8.08,46.67');
	const items = page.getByTestId('mymap-item');
	await expect(items).toHaveCount(3);

	// Any spelling of the tag; then at least 0.5 km.
	await page.getByTestId('mymap-tags').getByRole('button', { name: 'Winter' }).click();
	await expect(items).toHaveCount(2);
	await page.getByLabel('Distanz (km) von').fill('0.5');
	await page.getByLabel('Distanz (km) von').press('Enter');
	await expect(items).toHaveCount(1);
	await expect(items.first()).toContainText('Lang');
	await expect(items.first().getByTestId('tags')).toContainText('Tessin');

	// The address keeps the filters.
	await expect(page).toHaveURL(/tag=winter/i);
	await expect(page).toHaveURL(/dmin=0\.5/);
	await page.reload();
	await expect(items).toHaveCount(1);
	await expect(page.getByLabel('Distanz (km) von')).toHaveValue('0.5');
	await expect(
		page.getByTestId('mymap-tags').getByRole('button', { name: 'Winter' })
	).toHaveAttribute('aria-pressed', 'true');

	await items.first().getByRole('link', { name: 'Lang' }).click();
	await expect(page.getByTestId('route-title')).toHaveText('Lang');
});
