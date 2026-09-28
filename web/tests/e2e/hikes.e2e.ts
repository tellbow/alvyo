import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { linkFromMail } from './mailpit';

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
		/Gewandert am 20\.09\.2026 · 50\smin unterwegs · geplante Route/
	);
	await page.getByTestId('hike').getByRole('link', { name: 'geplante Route' }).click();
	await expect(page.getByTestId('route-title')).toHaveText('Bachalpsee');
});

test('others see a recorded hike without its start and end', async ({ page, browser }) => {
	const id = `priv${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Hiker',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const token = new URL(await linkFromMail(`${id}@example.ch`, '/verify-email')).searchParams.get(
		'token'
	);
	await page.request.post('/api/v1/auth/verify-email', { data: { token } });
	// A public hike east from 8.04, a position every 20 m: 2 km, and 600 m.
	const start = Date.UTC(2026, 8, 20, 8, 0);
	const upload = async (rec: string, n: number) => {
		const points = Array.from({ length: n }, (_, i) => ({
			lon: 8.04 + (i * 20) / 76_500,
			lat: 46.665,
			t: new Date(start + i * 60_000).toISOString()
		}));
		const res = await page.request.post('/api/v1/hikes', {
			data: { id: `${id}-${rec}`, title: `Weg ${rec}`, points }
		});
		const { id: routeId } = await res.json();
		const pub = await page.request.patch(`/api/v1/routes/${routeId}`, {
			data: { visibility: 'public' },
			headers: { 'If-Match': '"1"' }
		});
		expect(pub.status()).toBe(200);
		return routeId as string;
	};
	const long = await upload('lang', 101);
	const short = await upload('kurz', 31);

	await page.goto(`/routes/${long}`);
	await expect(page.getByTestId('hike-privacy')).toHaveText(
		/Andere sehen diese Wanderung ohne die ersten und letzten 500\sm\./
	);

	const context = await browser.newContext({ locale: 'de-CH' });
	const anon = await context.newPage();
	await anon.goto(`/routes/${long}`);
	await expect(anon.getByTestId('hike-privacy')).toHaveText(
		'Start und Ende der Wanderung sind verborgen.'
	);
	// 2 km less twice a little over 500 m.
	await expect(anon.getByTestId('stat-distance')).toHaveText(/^9\d\d\sm$/);
	await anon.goto(`/routes/${short}`);
	await expect(anon.getByTestId('hike-privacy')).toHaveText(/zu kurz, um sie anderen zu zeigen/);
	await expect(anon.getByTestId('route-stats')).toHaveCount(0);
	await context.close();
});
