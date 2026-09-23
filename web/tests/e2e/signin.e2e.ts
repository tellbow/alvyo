import { expect, test } from './fixtures';

const suffix = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

test('add a passkey, then log in with it without a password', async ({ page }) => {
	// Chromium's virtual authenticator stands in for the fingerprint reader.
	const cdp = await page.context().newCDPSession(page);
	await cdp.send('WebAuthn.enable');
	await cdp.send('WebAuthn.addVirtualAuthenticator', {
		options: {
			protocol: 'ctap2',
			transport: 'internal',
			hasResidentKey: true,
			hasUserVerification: true,
			isUserVerified: true,
			automaticPresenceSimulation: true
		}
	});

	const name = `pk${suffix()}`;
	const res = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${name}@example.ch`,
			username: name,
			display_name: 'Pia',
			password: 'sehr-geheim-123'
		}
	});
	expect(res.status()).toBe(201);

	await page.goto('/account');
	const methods = page.getByTestId('signin-methods');
	await methods.getByRole('button', { name: 'Passkey hinzufügen' }).click();
	await methods.getByLabel('Name, z. B. «Laptop» oder «iPhone»').fill('Testgerät');
	await methods.getByLabel('Passwort').fill('sehr-geheim-123');
	await methods.getByRole('button', { name: 'Passkey erstellen' }).click();
	await expect(methods.getByTestId('passkeys')).toContainText('Testgerät');

	await page.getByRole('button', { name: 'Abmelden' }).click();
	await page.goto('/login?redirect=/routes');
	await page.getByRole('button', { name: 'Mit Passkey anmelden' }).click();
	await expect(page).toHaveURL(/\/routes$/);
	await expect(page.getByTestId('current-user')).toHaveText(name);
});

test('sign up with a provider; an existing account connects it after logging in', async ({
	page,
	browser
}) => {
	// A new account through the provider, without password.
	const newcomer = `oi${suffix()}`;
	await page.goto('/signup');
	await page.getByRole('link', { name: 'Mit Test-ID registrieren' }).click();
	await page.getByLabel('E-Mail').fill(`${newcomer}@example.ch`);
	await page.getByLabel('Name').fill('Olivia Oidc');
	await page.getByRole('button', { name: 'Anmelden bei Test-ID' }).click();
	await expect(page).toHaveURL(/\/plan$/);
	await expect(page.getByTestId('current-user')).toHaveText(newcomer);
	await page.goto('/account');
	await expect(page.getByTestId('identities')).toContainText(`Test-ID · ${newcomer}@example.ch`);
	await expect(
		page.getByText('Dein Konto hat kein Passwort', { exact: false }).first()
	).toBeVisible();
	await page.getByTestId('identities').getByRole('button', { name: 'Trennen' }).click();
	await expect(page.getByTestId('signin-methods')).toContainText('Das ist dein letzter Weg');

	// Someone with a password account signs in at the provider with the same address.
	const owner = `ow${suffix()}`;
	const context = await browser.newContext();
	const tab = await context.newPage();
	const signup = await tab.request.post('/api/v1/auth/signup', {
		data: {
			email: `${owner}@example.ch`,
			username: owner,
			display_name: 'Otto',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	await tab.request.post('/api/v1/auth/logout');
	await tab.goto('/login');
	await tab.getByRole('link', { name: 'Mit Test-ID anmelden' }).click();
	await tab.getByLabel('E-Mail').fill(`${owner}@example.ch`);
	await tab.getByRole('button', { name: 'Anmelden bei Test-ID' }).click();
	await expect(tab.getByTestId('oidc-notice')).toContainText(
		'Zu dieser E-Mail-Adresse gibt es schon ein Konto'
	);
	// Log in with the password, then connect the provider from the account page.
	await tab.getByLabel('E-Mail oder Benutzername').fill(owner);
	await tab.getByLabel('Passwort').fill('sehr-geheim-123');
	await tab.getByRole('button', { name: 'Anmelden', exact: true }).click();
	await expect(tab.getByTestId('current-user')).toHaveText(owner);
	await tab.goto('/account');
	await tab.getByRole('link', { name: 'Test-ID verbinden' }).click();
	await tab.getByLabel('E-Mail').fill(`${owner}@example.ch`);
	await tab.getByRole('button', { name: 'Anmelden bei Test-ID' }).click();
	await expect(tab.getByTestId('oidc-notice')).toHaveText(
		'Verbunden. Du kannst dich jetzt auch damit anmelden.'
	);
	await expect(tab.getByTestId('identities')).toContainText('Test-ID');
	await context.close();
});
