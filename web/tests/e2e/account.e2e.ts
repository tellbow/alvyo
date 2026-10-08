import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('about page links to the source of this version', async ({ page }) => {
	await page.goto('/about');
	await expect(page.getByTestId('source-link')).toHaveAttribute(
		'href',
		'https://github.com/tellbow/alvyo'
	);
	await expect(page.getByText('© swisstopo')).toBeVisible();
});

test('delete the account', async ({ page }) => {
	const id = `del${Date.now().toString(36)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Del',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	await page.goto('/');
	await page.getByTestId('current-user').click();
	await expect(page).toHaveURL('/account');

	await page.getByLabel('Passwort').fill('falsches-passwort');
	await page.getByRole('button', { name: 'Konto endgültig löschen' }).click();
	await expect(page.getByRole('alert')).toHaveText('Das Passwort ist falsch.');

	await page.getByLabel('Passwort').fill('sehr-geheim-123');
	await page.getByRole('button', { name: 'Konto endgültig löschen' }).click();
	await expect(page).toHaveURL('/');
	await expect(page.getByRole('link', { name: 'Anmelden' })).toBeVisible();
	const login = await page.request.post('/api/v1/auth/login', {
		data: { login: id, password: 'sehr-geheim-123' }
	});
	expect(login.status()).toBe(401);
});

test("one's pace: chosen in the account, hiking times follow it", async ({ page }) => {
	const id = `pace${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pace',
			password: 'sehr-geheim-123'
		}
	});
	const created = await page.request.post('/api/v1/routes', {
		data: { title: 'Im eigenen Tempo', ...routeContent(8.04, 46.665, 60) }
	});
	const route = await created.json();
	// Rounded to five minutes, as on the page.
	const time = (s: number) => {
		const min = Math.round(s / 60 / 5) * 5;
		const h = Math.floor(min / 60);
		return h ? `${h}\u00a0h${min % 60 ? ` ${min % 60}\u00a0min` : ''}` : `${min}\u00a0min`;
	};

	await page.goto(`/routes/${route.id}`);
	await expect(page.getByTestId('stat-time')).toHaveText(time(route.totals.duration_s));

	await page.goto('/account');
	await expect(page.getByTestId('pace')).toHaveValue('1');
	await page.getByTestId('pace').selectOption('1.5');
	await expect
		.poll(async () => (await (await page.request.get('/api/v1/me')).json()).speed_factor)
		.toBe(1.5);

	await page.goto(`/routes/${route.id}`);
	await expect(page.getByTestId('stat-time')).toHaveText(time(route.totals.duration_s * 1.5));
	await page.goto('/account');
	await expect(page.getByTestId('pace')).toHaveValue('1.5');
});
