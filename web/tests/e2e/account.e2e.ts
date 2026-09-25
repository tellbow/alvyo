import { expect, test } from './fixtures';

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
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Del',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
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
