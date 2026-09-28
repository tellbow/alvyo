import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { linkFromMail } from './mailpit';

test('find a public route on the map, then its author', async ({ page }) => {
	const id = `disc${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const email = `${id}@example.ch`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: { email, username: id, display_name: 'Entdeckerin', password: 'sehr-geheim-123' }
	});
	expect(signup.status()).toBe(201);
	const token = new URL(await linkFromMail(email, '/verify-email')).searchParams.get('token');
	await page.request.post('/api/v1/auth/verify-email', { data: { token } });

	// A spot of its own, away from the routes of other tests.
	const lon = 7.2 + Math.random() * 2;
	const lat = 46.3 + Math.random() * 0.7;
	for (const [title, visibility] of [
		[`Aussichtsweg ${id}`, 'public'],
		[`Geheimweg ${id}`, 'private']
	]) {
		const res = await page.request.post('/api/v1/routes', {
			data: { title, visibility, ...routeContent(lon, lat) }
		});
		expect(res.status()).toBe(201);
	}

	await page.goto(
		`/discover?bbox=${[lon - 0.01, lat - 0.005, lon + 0.012, lat + 0.005].join(',')}`
	);
	const results = page.getByTestId('discover-results');
	const mine = results.getByTestId('discover-item').filter({ hasText: id });
	await expect(mine).toHaveCount(1);
	await expect(mine).toContainText(`Aussichtsweg ${id}`);
	await expect(mine).toContainText('T2');
	// Its start has a dot, to be found from afar.
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /collection-start/);

	// The route is T2, so it is gone when only T1 is allowed; the address keeps the filter.
	await page.getByLabel('Schwierigkeit').selectOption({ label: 'bis T1' });
	await expect(mine).toHaveCount(0);
	await expect(page).toHaveURL(/[?&]sac=1/);
	await page.getByLabel('Schwierigkeit').selectOption({ label: 'bis T3' });
	await expect(mine).toHaveCount(1);

	await mine.getByRole('link', { name: `von ${id}` }).click();
	await expect(page).toHaveURL(new RegExp(`/u/${id}$`));
	await expect(page.getByRole('heading', { name: 'Entdeckerin' })).toBeVisible();
	const routes = page.getByTestId('profile-routes');
	await expect(routes).toContainText(`Aussichtsweg ${id}`);
	await expect(routes).not.toContainText('Geheimweg');

	await routes.getByRole('link').first().click();
	await expect(page.getByTestId('route-title')).toHaveText(`Aussichtsweg ${id}`);
	await expect(page.getByRole('link', { name: `von ${id}` })).toHaveAttribute('href', `/u/${id}`);
});

test('users without public tours have no profile', async ({ page }) => {
	const res = await page.goto('/u/niemand_hier');
	expect(res?.status()).toBe(404);
});
