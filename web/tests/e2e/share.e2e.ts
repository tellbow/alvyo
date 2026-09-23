import { expect, test } from './fixtures';
import { linkFromMail } from './mailpit';

test('share a route by link with someone without an account', async ({
	page,
	context,
	browser
}) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'odysgeh.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 14
			})
		);
	});
	const id = `share${Date.now().toString(36)}`;
	const email = `${id}@example.ch`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: { email, username: id, display_name: 'Sharer', password: 'sehr-geheim-123' }
	});
	expect(signup.status()).toBe(201);
	const token = new URL(await linkFromMail(email, '/verify-email')).searchParams.get('token');
	expect((await page.request.post('/api/v1/auth/verify-email', { data: { token } })).status()).toBe(
		204
	);

	await page.goto('/plan');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
	const box = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
	await page.mouse.click(box.x + box.width / 2 - 250, box.y + box.height / 2 + 80);
	await page.mouse.click(box.x + box.width / 2 + 250, box.y + box.height / 2 + 40);
	await expect(page.getByTestId('leg').nth(0)).toHaveAttribute('data-state', 'ok', {
		timeout: 15_000
	});

	const panel = page.getByTestId('save-panel');
	await panel.getByLabel('Titel').fill('Geteilte Runde');
	await panel.getByLabel('Sichtbarkeit').selectOption('unlisted');
	await panel.getByRole('button', { name: 'Speichern' }).click();
	await expect(page).toHaveURL(/\/plan\/[0-9a-f-]{36}$/);
	const shareUrl = await page.getByTestId('share-link').locator('input').inputValue();
	expect(shareUrl).toMatch(/\/routes\/[0-9a-f-]{36}\?t=[\w-]{22}$/);

	// Someone without an account opens the link.
	const guest = await (await browser.newContext()).newPage();
	await guest.goto(shareUrl);
	await expect(guest.getByTestId('route-title')).toHaveText('Geteilte Runde');
	await expect(guest.getByRole('link', { name: 'Bearbeiten' })).toHaveCount(0);
	// Link previews: Open Graph tags point at a rendered image the guest may load.
	const ogImage = await guest.locator('meta[property="og:image"]').getAttribute('content');
	expect(ogImage).toMatch(/\/og\.png\?v=\d+&t=[\w-]{22}$/);
	const image = await guest.request.get(ogImage!);
	expect(image.status()).toBe(200);
	expect(image.headers()['content-type']).toBe('image/png');
	await (await import('node:fs/promises')).writeFile('test-results/og.png', await image.body());
	// Without the token they are asked to log in, as for a route that does
	// not exist at all: nothing tells them it exists.
	await guest.goto(shareUrl.replace(/\?t=.*/, ''));
	await expect(guest).toHaveURL(/\/login\?redirect=%2Froutes%2F/);
	await guest.goto('/routes/00000000-0000-4000-8000-000000000000');
	await expect(guest).toHaveURL(/\/login\?redirect=%2Froutes%2F0{8}/);

	// A new link invalidates the old one.
	await page.getByRole('button', { name: 'Neuen Link erzeugen' }).click();
	await expect(page.getByTestId('share-link').locator('input')).not.toHaveValue(shareUrl);
	expect((await guest.goto(shareUrl))?.status()).toBe(404);
});
