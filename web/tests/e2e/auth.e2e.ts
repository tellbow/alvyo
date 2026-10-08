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

	// Not logged in yet: first the address.
	await expect(page.getByTestId('signup-sent')).toContainText(`eine E-Mail an ${email}`);
	await page.goto('/login');
	await page.getByLabel('E-Mail oder Benutzername').fill(id);
	await page.getByLabel('Passwort').fill(password);
	await page.getByRole('button', { name: 'Anmelden', exact: true }).click();
	await expect(page.getByRole('alert')).toHaveText(
		'Bestätige zuerst deine E-Mail-Adresse. Wir haben dir einen neuen Link geschickt.'
	);

	// The link names the account and logs in once confirmed.
	await page.goto(await linkFromMail(email, '/verify-email'));
	await expect(page.getByText(`Konto «${id}» (E2E Test) bestätigen?`)).toBeVisible();
	await page.getByTestId('verify-confirm').click();
	await expect(page.getByTestId('verify-status')).toContainText(
		'Deine E-Mail-Adresse ist bestätigt.'
	);
	await expect(page.getByTestId('current-user')).toHaveText(id);

	// The same address again: the same answer, no hint that it has an account.
	const again = await page.context().browser()!.newContext();
	const other = await again.newPage();
	await other.goto('/signup');
	await other.getByLabel('E-Mail').fill(email);
	await other.getByLabel('Benutzername').fill(`${id}x`);
	await other.getByLabel('Anzeigename').fill('Jemand');
	await other.getByLabel('Passwort').fill(password);
	await other.getByRole('button', { name: 'Konto erstellen' }).click();
	await expect(other.getByTestId('signup-sent')).toContainText(`eine E-Mail an ${email}`);
	await again.close();

	await page.getByRole('button', { name: 'Abmelden', exact: true }).click();
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
