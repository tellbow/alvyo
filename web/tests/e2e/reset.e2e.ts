import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { linkFromMail } from './mailpit';

test('forgotten password: link by e-mail, new password, log in', async ({ page }) => {
	const id = `e2e${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const email = `${id}@example.ch`;
	const signup = await signUp(page.request, {
		data: { email, username: id, display_name: 'Reset', password: 'altes-passwort-123' }
	});
	expect(signup.ok()).toBeTruthy();
	await page.request.post('/api/v1/auth/logout');
	await page.context().clearCookies();

	await page.goto('/forgot-password');
	await page.getByLabel('E-Mail').fill(email);
	await page.getByRole('button', { name: 'Link senden' }).click();
	await expect(page.getByRole('status')).toHaveText(
		'Falls ein Konto zu dieser Adresse existiert, ist eine E-Mail unterwegs.'
	);

	const link = await linkFromMail(email, '/reset-password');
	await page.goto(link);
	await page.getByLabel('Neues Passwort').fill('neues-passwort-456');
	await page.getByRole('button', { name: 'Passwort speichern' }).click();
	await expect(page.getByText('Passwort geändert. Du kannst dich jetzt anmelden.')).toBeVisible();

	// The link works once.
	await page.goto(link);
	await page.getByLabel('Neues Passwort').fill('noch-ein-passwort-789');
	await page.getByRole('button', { name: 'Passwort speichern' }).click();
	await expect(
		page.getByText('Der Link ist ungültig oder abgelaufen.', { exact: false })
	).toBeVisible();

	await page.goto('/login');
	await page.getByLabel('E-Mail oder Benutzername').fill(email);
	await page.getByLabel('Passwort').fill('neues-passwort-456');
	await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
	await expect(page.getByTestId('current-user')).toHaveText(id);
});
