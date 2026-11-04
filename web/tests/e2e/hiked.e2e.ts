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

test('what I hiked stays mine until I share it, each part on its own', async ({
	page,
	browser
}) => {
	const id = `shr${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Teilerin',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	// Long enough that something is left without the first and last 500 m.
	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Geheimer Weg', ...routeContent(8.04, 46.665, 100) }
	});
	expect(res.status()).toBe(201);
	const route = (await res.json()).id;
	const done = await page.request.put(`/api/v1/routes/${route}/done`, {
		data: { done_on: '2026-08-01' }
	});
	expect(done.status()).toBe(200);

	const anon = await (await browser.newContext({ locale: 'de-CH' })).newPage();
	expect((await anon.goto(`/u/${id}/hiked`))?.status()).toBe(404);

	// One's own page has the achievements, for oneself alone.
	await page.goto('/hiked');
	await expect(page.getByTestId('achievements')).toContainText('Kantone: 1 von 26');
	await expect(page.getByTestId('achievement-cantons')).toContainText('BE');

	await page.goto('/account');
	await page.getByTestId('share_stats').selectOption('public');
	await expect
		.poll(async () => (await page.request.get('/api/v1/me')).json())
		.toMatchObject({ share_stats: 'public', share_map: 'nobody' });

	await anon.goto(`/u/${id}/hiked`);
	await expect(anon.getByTestId('hiked-stats')).toContainText('Wanderungen 1');
	await expect(anon.getByTestId('achievements')).toHaveCount(0);
	await expect(anon.locator('canvas')).toHaveCount(0);

	await page.getByTestId('share_map').selectOption('public');
	await page.getByTestId('share_achievements').selectOption('public');
	await expect
		.poll(async () => (await page.request.get('/api/v1/me')).json())
		.toMatchObject({ share_map: 'public', share_achievements: 'public' });

	// Through the profile: the map and the rest, and never the route's title.
	await anon.goto(`/u/${id}`);
	await anon.getByTestId('profile-hiked').click();
	await expect(anon).toHaveURL(new RegExp(`/u/${id}/hiked$`));
	await expect(anon.locator('canvas').first()).toBeVisible();
	await expect(anon.getByTestId('achievements')).toContainText('BE');
	await expect(anon.getByTestId('shared-hiked')).not.toContainText('Geheimer Weg');

	await anon.context().close();
});
