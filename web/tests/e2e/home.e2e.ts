import { signUp } from './accounts';
import { expect, test } from './fixtures';

test('the home page: a place leads to the hikes around it', async ({ page }) => {
	const id = `home${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Home',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);

	await page.goto('/');
	await expect(page.getByRole('heading', { level: 1 })).toHaveText(
		'Wandern, bis die Karte aufhört.'
	);
	await expect(page.getByTestId('language')).toBeEnabled(); // hydrated

	await page.getByLabel('Region, Gipfel oder Hütte').fill('Gitschenen');
	await page
		.getByRole('option', { name: /^Gitschenen/ })
		.first()
		.click();
	await expect(page).toHaveURL(/\/discover\?bbox=8\.\d+,46\.\d+,8\.\d+,46\.\d+/);
	await expect(page.getByRole('heading', { name: 'Touren entdecken' })).toBeVisible();
});
