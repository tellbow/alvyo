import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('a hike recorded with the app shows when it was hiked and its planned route', async ({
	page
}) => {
	const id = `hike${Date.now().toString(36)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Hiker',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const planned = await page.request.post('/api/v1/routes', {
		data: { title: 'Bachalpsee', visibility: 'private', ...routeContent(8.04, 46.665) }
	});
	const { id: plannedId } = await planned.json();

	// As the app uploads it: a position every 20 m and minute, 1 km east.
	const start = Date.UTC(2026, 8, 20, 8, 0);
	const points = Array.from({ length: 51 }, (_, i) => ({
		lon: 8.04 + (i * 20) / 76_500,
		lat: 46.665,
		t: new Date(start + i * 60_000).toISOString()
	}));
	const body = { id: `${id}-rec`, route_id: plannedId, title: 'Bachalpsee, 20.09.2026', points };
	const upload = await page.request.post('/api/v1/hikes', { data: body });
	expect(upload.status()).toBe(201);
	const again = await page.request.post('/api/v1/hikes', { data: body });
	expect(again.status()).toBe(200); // the app retried: no second route

	await page.goto('/routes');
	const hike = page
		.getByTestId('route-list')
		.locator(':scope > li', { hasText: /Bachalpsee, 20\.09\.2026/ });
	await expect(hike).toContainText('Gewandert am 20.09.2026');
	await hike.getByRole('link', { name: /Bachalpsee/ }).click();
	await expect(page.getByTestId('hike')).toHaveText(
		/Gewandert am 20\.09\.2026 · 50 min unterwegs · geplante Route/
	);
	await page.getByTestId('hike').getByRole('link', { name: 'geplante Route' }).click();
	await expect(page.getByTestId('route-title')).toHaveText('Bachalpsee');
});
