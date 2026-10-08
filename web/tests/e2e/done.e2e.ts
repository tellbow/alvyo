import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('mark a route as hiked; the list and the map tell planned from hiked', async ({ page }) => {
	const s = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `done${s}@example.ch`,
			username: `done${s}`,
			display_name: 'Done',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	const create = async (title: string, lon: number) =>
		(
			await (
				await page.request.post('/api/v1/routes', { data: { title, ...routeContent(lon, 46.665) } })
			).json()
		).id as string;
	const hiked = await create('Schon gewandert', 8.04);
	await create('Noch geplant', 8.06);

	await page.goto(`/routes/${hiked}`);
	await page.getByTestId('done').click();
	await page.getByTestId('done-day').fill('2026-08-01');
	await page.getByTestId('done-save').click();
	await expect(page.getByTestId('done')).toHaveText('✓ 1.8.2026');

	await page.goto('/routes');
	const list = page.getByTestId('route-list');
	await expect(list.getByTestId('done-on')).toHaveText('✓ Gewandert am 1.8.2026');
	await page.getByTestId('done-filter').getByRole('link', { name: 'Geplant' }).click();
	await expect(page).toHaveURL(/\?done=planned$/);
	await expect(list).toContainText('Noch geplant');
	await expect(list).not.toContainText('Schon gewandert');

	// On the map of one's hikes too.
	await page.goto('/routes/map?done=done');
	await expect(
		page.getByTestId('mymap-done').getByRole('button', { name: 'Gewandert' })
	).toHaveAttribute('aria-pressed', 'true');

	// Taken back.
	await page.goto(`/routes/${hiked}`);
	await page.getByTestId('done').click();
	await page.getByTestId('done-remove').click();
	await expect(page.getByTestId('done')).toHaveText('✓ Gewandert');
});
