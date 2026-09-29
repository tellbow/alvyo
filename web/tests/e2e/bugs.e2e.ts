import { writeFileSync } from 'node:fs';
import { expect, test } from './fixtures';

test('a bug reported from the planner, with what is open and a screenshot', async ({ page }) => {
	const id = `bug${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Melder',
			password: 'sehr-geheim-123'
		}
	});
	await page.goto('/plan?t=geheim');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\bovl-wanderwege\b/);
	await page.getByRole('button', { name: 'Fehler melden' }).click();
	const dialog = page.getByRole('dialog', { name: 'Fehler melden' });
	await expect(dialog.getByRole('img', { name: 'Bildschirmfoto dieser Seite' })).toBeVisible();
	await expect(dialog).toContainText('Mit dem Bericht gehen die Adresse (/plan)');
	await dialog.getByTestId('bug-text').fill('Die Karte bleibt leer.');
	const sent = page.waitForRequest((r) => r.url().endsWith('/api/v1/bug-reports'));
	await dialog.getByTestId('bug-send').click();
	await expect(dialog.getByTestId('bug-sent')).toBeVisible();
	const body = (await sent).postDataJSON();
	expect(body).toMatchObject({
		description: 'Die Karte bleibt leer.',
		place: '/plan',
		platform: 'web'
	});
	expect(body.screenshot.length).toBeGreaterThan(10_000);
	const jpeg = Buffer.from(body.screenshot, 'base64');
	expect(jpeg.subarray(0, 2)).toEqual(Buffer.from([0xff, 0xd8]));
	writeFileSync('test-results/bug-screenshot.jpg', jpeg);
});

test('not for visitors', async ({ page }) => {
	await page.goto('/discover');
	await expect(page.getByTestId('bug-open')).toHaveCount(0);
});
