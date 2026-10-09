import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test("someone's public route as one's own, and discovery by origin", async ({ page }) => {
	const id = `copy${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const lon = 7.2 + Math.random() * 2;
	const lat = 46.3 + Math.random() * 0.7;
	const account = (name: string) => ({
		data: {
			email: `${name}@example.ch`,
			username: name,
			display_name: name,
			password: 'sehr-geheim-123'
		}
	});
	expect((await signUp(page.request, account(`${id}a`))).status()).toBe(200);
	const res = await page.request.post('/api/v1/routes', {
		data: { title: `Seeweg ${id}`, visibility: 'public', ...routeContent(lon, lat) }
	});
	expect(res.status()).toBe(201);
	const original = (await res.json()).id;
	await page.request.post('/api/v1/auth/logout');

	// Logged out: the button leads to the login and back.
	await page.goto(`/routes/${original}`);
	await expect(page.getByTestId('copy')).toHaveAttribute(
		'href',
		`/login?redirect=${encodeURIComponent(`/routes/${original}`)}`
	);

	expect((await signUp(page.request, account(`${id}b`))).status()).toBe(200);
	await page.goto(`/routes/${original}`);
	await page.getByRole('button', { name: 'Als eigene Route bearbeiten' }).click();
	await expect(page).toHaveURL(/\/plan\/[0-9a-f-]{36}$/);
	const copy = page.url().split('/').pop()!;
	expect(copy).not.toBe(original);
	const saved = await (await page.request.get(`/api/v1/routes/${copy}`)).json();
	expect(saved).toMatchObject({
		title: `Seeweg ${id}`,
		owner_username: `${id}b`,
		visibility: 'private',
		can_edit: true
	});

	// People's routes, not official ones; the address keeps the choice.
	await page.goto(
		`/discover?bbox=${[lon - 0.01, lat - 0.005, lon + 0.012, lat + 0.005].join(',')}`
	);
	const mine = page.getByTestId('discover-item').filter({ hasText: id });
	await expect(mine).toHaveCount(1);
	await page.getByLabel('Herkunft').selectOption({ label: 'Nur offizielle Routen' });
	await expect(mine).toHaveCount(0);
	await expect(page).toHaveURL(/[?&]origin=only/);
	await page.getByLabel('Herkunft').selectOption({ label: 'Nur von Leuten' });
	await expect(mine).toHaveCount(1);
});
