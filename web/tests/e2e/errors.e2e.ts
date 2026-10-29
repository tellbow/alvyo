import { expect, test } from './fixtures';

test('an unknown address says so in the reader’s language, with a way back', async ({
	page,
	browser
}) => {
	const res = await page.goto('/gibt-es-nicht');
	expect(res?.status()).toBe(404);
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('Diese Seite gibt es nicht');
	await page.getByRole('link', { name: 'Zur Startseite' }).click();
	await expect(page.getByRole('heading', { level: 1 })).toHaveText('Plane deine nächste Wanderung');

	const context = await browser.newContext({ locale: 'fr-CH' });
	const fr = await context.newPage();
	await fr.goto('/fr/gibt-es-nicht');
	await expect(fr.getByRole('heading', { level: 1 })).toHaveText("Cette page n'existe pas");
	await context.close();
});
