import { writeFileSync } from 'node:fs';
import { signUp } from './accounts';
import { expect, test } from './fixtures';

test('a bug reported from the planner, with what is open and a screenshot', async ({ page }) => {
	const id = `bug${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Melder',
			password: 'sehr-geheim-123'
		}
	});
	await page.goto('/plan?t=geheim');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\bovl-wanderwege\b/);
	const map = (await page.getByTestId('map').boundingBox())!;
	await page.waitForTimeout(2000); // tiles
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
	writeFileSync(`test-results/bug-screenshot-${test.info().project.name}.jpg`, jpeg);

	// The map is in it (Safari drew it empty): many colours where it lies.
	const colours = await page.evaluate(
		async ({ src, map }) => {
			const img = new Image();
			img.src = src;
			await img.decode();
			const scale = img.width / document.body.clientWidth;
			const c = document.createElement('canvas');
			c.width = img.width;
			c.height = img.height;
			const ctx = c.getContext('2d')!;
			ctx.drawImage(img, 0, 0);
			const d = ctx.getImageData(
				map.x * scale,
				map.y * scale,
				map.width * scale,
				map.height * scale
			).data;
			const seen = new Set<number>();
			for (let i = 0; i < d.length; i += 4 * 7)
				seen.add((d[i] >> 4) * 256 + (d[i + 1] >> 4) * 16 + (d[i + 2] >> 4));
			return seen.size;
		},
		{ src: `data:image/jpeg;base64,${body.screenshot}`, map }
	);
	expect(colours, 'colours in the map').toBeGreaterThan(300);
});

test('not for visitors', async ({ page }) => {
	await page.goto('/discover');
	await expect(page.getByTestId('bug-open')).toHaveCount(0);
});
