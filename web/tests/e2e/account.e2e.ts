import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('about page links to the source of this version', async ({ page }) => {
	await page.goto('/about');
	await expect(page.getByTestId('source-link')).toHaveAttribute(
		'href',
		'https://github.com/tellbow/alvyo'
	);
	await expect(page.getByTestId('notice-link')).toHaveAttribute(
		'href',
		/^https:\/\/github\.com\/tellbow\/alvyo\/blob\/.+\/NOTICE$/
	);
});

test('about page credits every data source and names the operator', async ({ page }) => {
	await page.goto('/about');
	const sources = page.getByTestId('data-sources');
	await expect(sources.getByRole('listitem')).toHaveCount(11);
	await expect(sources.getByRole('link', { name: 'OGD, © swisstopo' })).toBeVisible();
	await expect(sources.getByRole('link', { name: 'ODbL' })).toHaveAttribute(
		'href',
		'https://www.openstreetmap.org/copyright'
	);
	await expect(sources).toContainText('Quelle: MeteoSchweiz');
	await expect(sources).toContainText('Wanderwegen (opendata.swiss)');
	await expect(page.getByTestId('operator')).toContainText('Alvyo Test');
	await expect(page.getByTestId('operator')).toContainText('Wanderweg 1, 3000 Bern');
	await expect(page.getByTestId('operator')).toContainText('hallo@alvyo.test');
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

test('an access token: shown once, reads, revoked', async ({ page, playwright, baseURL }) => {
	const id = `pat${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pat',
			password: 'sehr-geheim-123'
		}
	});
	await page.goto('/account');
	await expect(page.getByTestId('mcp-url')).toHaveText(`${baseURL}/api/v1/mcp`);
	await page.getByTestId('token-name').fill('Claude Desktop');
	await page.getByTestId('token-create').click();
	const token = (await page.getByTestId('token-value').textContent()) ?? '';
	expect(token).toMatch(/^alvyo_pat_/);
	await expect(page.getByTestId('tokens')).toContainText('Claude Desktop');
	await expect(page.getByTestId('tokens')).toContainText('noch nie benutzt');

	// Without the browser's cookie: the token alone reads, and writes nothing.
	const script = await playwright.request.newContext({
		baseURL,
		extraHTTPHeaders: { Authorization: `Bearer ${token}` }
	});
	expect((await script.get('/api/v1/me')).status()).toBe(200);
	expect((await script.post('/api/v1/routes', { data: {} })).status()).toBe(403);

	// Shown once: not after loading the page again.
	await page.reload();
	await expect(page.getByTestId('token-value')).toHaveCount(0);
	await expect(page.getByTestId('tokens')).toContainText('zuletzt benutzt');

	await page.getByRole('button', { name: 'Widerrufen' }).click();
	await expect(page.getByTestId('revoke-confirm')).toContainText('«Claude Desktop» widerrufen?');
	await page.getByTestId('revoke-confirm').getByRole('button', { name: 'Widerrufen' }).click();
	await expect(page.getByTestId('tokens')).not.toContainText('Claude Desktop');
	expect((await script.get('/api/v1/me')).status()).toBe(401);
	await script.dispose();
});
