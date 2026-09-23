import { readFileSync } from 'node:fs';
import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { linkFromMail } from './mailpit';

// 800×600 JPEG with EXIF: taken ~20 m from the route below, 4 July 2026.
const alongTheRoute = readFileSync(new URL('files/along-the-route.jpg', import.meta.url));
// A 1×1 PNG without any position.
const plainPng = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
	'base64'
);

test('photos: upload, pin along the route, caption and view', async ({ page, browser }) => {
	await page.setViewportSize({ width: 1400, height: 900 });
	const id = `pho${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const email = `${id}@example.ch`;
	await page.request.post('/api/v1/auth/signup', {
		data: { email, username: id, display_name: 'Paula Photo', password: 'sehr-geheim-123' }
	});
	const token = new URL(await linkFromMail(email, '/verify-email')).searchParams.get('token');
	await page.request.post('/api/v1/auth/verify-email', { data: { token } });
	const created = await page.request.post('/api/v1/routes', {
		data: { title: `Fotoweg ${id}`, visibility: 'public', ...routeContent(8.04, 46.665) }
	});
	const route = (await created.json()).id as string;

	await page.goto(`/routes/${route}`);
	const photos = page.getByTestId('photos');
	await photos.locator('input[type=file]').setInputFiles([
		{ name: 'along-the-route.jpg', mimeType: 'image/jpeg', buffer: alongTheRoute },
		{ name: 'plan.png', mimeType: 'image/png', buffer: plainPng }
	]);
	await expect(photos.getByRole('listitem')).toHaveCount(2);
	// Only the photo taken along the route is on the map.
	await expect(page.getByTestId('photo-pin')).toHaveCount(1);

	await page.getByTestId('photo-pin').click();
	const lightbox = page.getByTestId('lightbox');
	await expect(lightbox).toContainText('1 / 2');
	await expect(lightbox).toContainText('04.07.2026');
	await lightbox.getByLabel('Beschreibung').fill('Blick zum Eiger');
	await lightbox.getByLabel('Beschreibung').press('Tab');
	await lightbox.getByRole('button', { name: 'Nächstes Foto' }).click();
	await expect(lightbox).toContainText('2 / 2');
	await lightbox.getByRole('button', { name: 'Löschen' }).click();
	await lightbox.getByRole('button', { name: 'Wirklich löschen?' }).click();
	await expect(lightbox).toHaveCount(0);
	await expect(photos.getByRole('listitem')).toHaveCount(1);

	// Visitors see the photo and its caption, without edit controls.
	const visitor = await browser.newContext({ viewport: { width: 1400, height: 900 } });
	const visitorPage = await visitor.newPage();
	await visitorPage.goto(`/routes/${route}`);
	await visitorPage.getByTestId('photos').getByRole('button', { name: 'Blick zum Eiger' }).click();
	const view = visitorPage.getByTestId('lightbox');
	await expect(view).toContainText('Blick zum Eiger');
	await expect(view).toContainText(`von ${id}`);
	await expect(view.getByLabel('Beschreibung')).toHaveCount(0);
	const loaded = await view
		.getByRole('img', { name: 'Blick zum Eiger' })
		.evaluate((img: HTMLImageElement) => img.decode().then(() => img.naturalWidth));
	expect(loaded).toBe(800);
	await visitorPage.keyboard.press('Escape');
	await expect(view).toHaveCount(0);
	await visitor.close();
});
