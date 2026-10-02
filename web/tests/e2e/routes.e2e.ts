import { expect, test } from './fixtures';

test('save a planned route, reopen and edit it, then delete it', async ({ page, context }) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 14
			})
		);
	});
	const id = `save${Date.now().toString(36)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Saver',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const legRequests: string[] = [];
	page.on('request', (r) => r.url().includes('/api/v1/routing/leg') && legRequests.push(r.url()));

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
	const box = (await canvas.boundingBox())!;
	const at = (dx: number, dy: number) =>
		[box.x + box.width / 2 + dx, box.y + box.height / 2 + dy] as const;
	await page.mouse.click(...at(-250, 80));
	await page.mouse.click(...at(250, 40));
	const legs = page.getByTestId('leg');
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });

	const panel = page.getByTestId('save-panel');
	await panel.getByLabel('Titel').fill('Bachalpsee Runde');
	await panel.getByRole('button', { name: 'Speichern' }).click();
	await expect(page).toHaveURL(/\/plan\/[0-9a-f-]{36}$/);
	const routeUrl = page.url();

	// Reloading resumes the route from storage: no routing requests.
	const before = legRequests.length;
	await page.reload();
	await expect(page.getByTestId('leg').nth(0)).toHaveAttribute('data-state', 'ok');
	await expect(page.getByTestId('anchor')).toHaveCount(2);
	expect(legRequests.length).toBe(before);
	await expect(panel.getByRole('button', { name: 'Speichern' })).toBeDisabled(); // nothing changed

	// Extend the route and save the change.
	await page.mouse.click(...at(100, -150));
	await expect(page.getByTestId('leg')).toHaveCount(2);
	await expect(page.getByTestId('leg').nth(1)).toHaveAttribute('data-state', 'ok', {
		timeout: 15_000
	});
	await panel.getByRole('button', { name: 'Speichern' }).click();
	await expect(panel.getByRole('status')).toHaveText('Gespeichert');
	await page.reload();
	await expect(page.getByTestId('anchor')).toHaveCount(3);

	// Listed under "Meine Routen", with a read-only page.
	await page.getByRole('link', { name: 'Meine Routen' }).click();
	await page.getByRole('link', { name: /Bachalpsee Runde/ }).click();
	await expect(page.getByTestId('route-title')).toHaveText('Bachalpsee Runde');
	await expect(page.getByTestId('stat-sac')).toContainText(/T\d/);
	await page.screenshot({ path: 'test-results/route-view.png' });

	const [download] = await Promise.all([
		page.waitForEvent('download'),
		page.getByRole('link', { name: 'GPX herunterladen' }).click()
	]);
	expect(download.suggestedFilename()).toBe('bachalpsee-runde.gpx');
	const gpx = await (await import('node:fs/promises')).readFile((await download.path())!, 'utf8');
	expect(gpx).toContain('<trkpt');
	expect(gpx).toContain('<ele>');

	await page.getByTestId('route-menu').click();
	await page.getByRole('button', { name: 'Löschen' }).click();
	await page.getByRole('button', { name: 'Wirklich löschen?' }).click();
	await expect(page).toHaveURL('/routes');
	await expect(page.getByText('Noch keine Routen')).toBeVisible();
	expect((await page.request.get(routeUrl.replace('/plan/', '/api/v1/routes/'))).status()).toBe(
		404
	);
});
