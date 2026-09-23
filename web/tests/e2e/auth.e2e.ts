import { expect, test } from './fixtures';
import { linkFromMail } from './mailpit';

test('sign up, verify e-mail, log out and log in again', async ({ page }) => {
	const id = `e2e${Date.now().toString(36)}`;
	const email = `${id}@example.ch`;
	const password = 'sehr-geheim-123';

	await page.goto('/signup');
	// Never GET: a form submitted before hydration must not put the password in the URL.
	await expect(page.locator('form')).toHaveAttribute('method', 'post');
	await page.getByLabel('E-Mail').fill(email);
	await page.getByLabel('Benutzername').fill(id);
	await page.getByLabel('Anzeigename').fill('E2E Test');
	await page.getByLabel('Passwort').fill(password);
	await page.getByRole('button', { name: 'Konto erstellen' }).click();

	await expect(page).toHaveURL('/plan');
	await expect(page.getByTestId('current-user')).toHaveText(id);
	await expect(page.getByText('Bitte bestätige deine E-Mail-Adresse')).toBeVisible();

	await page.goto(await linkFromMail(email, '/verify-email'));
	await expect(page.getByTestId('verify-status')).toHaveText('Deine E-Mail-Adresse ist bestätigt.');
	await expect(page.getByText('Bitte bestätige deine E-Mail-Adresse')).toBeHidden();

	await page.getByRole('button', { name: 'Abmelden' }).click();
	await expect(page.getByRole('link', { name: 'Anmelden' })).toBeVisible();

	await page.goto('/login?redirect=/plan');
	await page.getByLabel('E-Mail oder Benutzername').fill(email);
	await page.getByLabel('Passwort').fill('falsches-passwort');
	await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveText('E-Mail/Benutzername oder Passwort ist falsch.');

	await page.getByLabel('Passwort').fill(password);
	await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
	await expect(page).toHaveURL('/plan');
	await expect(page.getByTestId('current-user')).toHaveText(id);

	// Server-side rendering sees the session too.
	await page.reload();
	await expect(page.getByTestId('current-user')).toHaveText(id);
});
