import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('what I hiked: on a map, by year, a route hiked again counts again', async ({ page }) => {
	const id = `hik${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Hiker',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);

	await page.goto('/hiked');
	await expect(page.getByTestId('hiked-empty')).toBeVisible();

	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Zweimal', ...routeContent(8.04, 46.665, 20) }
	});
	expect(res.status()).toBe(201);
	const route = (await res.json()).id;

	// Marked once, then again with «Nochmals gewandert» on another day.
	await page.goto(`/routes/${route}`);
	await page.getByTestId('done').click();
	await page.getByTestId('done-day').fill('2025-08-01');
	await page.getByTestId('done-save').click();
	await expect(page.getByTestId('done')).toHaveText('✓ 1.8.2025');
	await page.getByTestId('done').click();
	await page.getByTestId('done-day').fill('2026-08-01');
	await expect(page.getByTestId('done-save')).toHaveText('✓ Nochmals gewandert');
	await page.getByTestId('done-save').click();
	await expect(page.getByTestId('done')).toHaveText('✓ 1.8.2026');

	await page.goto('/routes');
	await page.getByRole('link', { name: 'Meine Wanderungen' }).click();
	await expect(page).toHaveURL(/\/hiked$/);
	const stats = page.getByTestId('hiked-stats');
	await expect(stats).toContainText('Wanderungen 2');
	await expect(page.getByTestId('hiked-item')).toHaveCount(2);

	await page.getByRole('link', { name: '2025', exact: true }).click();
	await expect(page).toHaveURL(/\?year=2025$/);
	await expect(stats).toContainText('Wanderungen 1');
	await expect(page.getByTestId('hiked-item')).toHaveCount(1);
	await expect(page.getByTestId('hiked-item')).toContainText('1.8.2025');
	await page.getByTestId('hiked-item').getByRole('link').click();
	await expect(page).toHaveURL(new RegExp(`/routes/${route}`));
});
