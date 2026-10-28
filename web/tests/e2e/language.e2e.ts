import { expect, test } from './fixtures';

test('the language follows the browser and can be switched', async ({ browser }) => {
	const context = await browser.newContext({ locale: 'fr-CH' });
	const page = await context.newPage();
	// Each language has its own address; German has no prefix.
	await page.goto('/about');
	await expect(page).toHaveURL(/\/fr\/about$/);
	await expect(page.getByRole('heading', { level: 1 })).toHaveText("À propos d'Alvyo");
	await expect(page.locator('html')).toHaveAttribute('lang', 'fr');

	await page.getByTestId('language').click();
	await page.getByRole('menuitemradio', { name: 'Italiano' }).click();
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('Informazioni su Alvyo');
	await expect(page).toHaveURL(/\/it\/about$/);
	// The choice wins over an address in another language.
	await page.goto('/fr/discover');
	await expect(page).toHaveURL(/\/it\/discover$/);
	await expect(page.getByRole('link', { name: 'Scopri' })).toBeVisible();
	await context.close();
});
