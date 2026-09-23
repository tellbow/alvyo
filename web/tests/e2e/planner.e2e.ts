import { expect, test } from './fixtures';

test('plan a route by clicking the map, then adjust it', async ({ page, context }) => {
	// Start zoomed in near Grindelwald First, where trails are dense.
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
	const id = `plan${Date.now().toString(36)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planner',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	const legRequests: string[] = [];
	page.on('request', (r) => r.url().includes('/api/v1/routing/leg') && legRequests.push(r.url()));

	await page.goto('/plan');
	const canvas = page.locator('canvas.maplibregl-canvas');
	await expect(canvas).toBeVisible();
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
	const box = (await canvas.boundingBox())!;
	const at = (dx: number, dy: number) => ({
		x: box.x + box.width / 2 + dx,
		y: box.y + box.height / 2 + dy
	});

	for (const p of [at(-250, 80), at(0, -60), at(250, 40)]) {
		await page.mouse.click(p.x, p.y);
	}
	await expect(page.getByTestId('anchor')).toHaveCount(3);
	const legs = page.getByTestId('leg');
	await expect(legs).toHaveCount(2);
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });
	expect(legRequests).toHaveLength(2);

	await expect(page.getByTestId('stat-distance')).toContainText(/\d/);
	await expect(page.getByTestId('stat-time')).toContainText(/min|h/);
	await expect(page.getByTestId('stat-sac')).toContainText(/T\d/);
	await expect(page.getByTestId('elevation-profile')).toBeVisible();
	await page.screenshot({ path: 'test-results/planner.png' });

	// Dragging the middle anchor recomputes exactly its two adjacent legs.
	const middle = (await page.getByTestId('anchor').nth(1).boundingBox())!;
	await page.mouse.move(middle.x + middle.width / 2, middle.y + middle.height / 2);
	await page.mouse.down();
	await page.mouse.move(middle.x + 60, middle.y + 90, { steps: 8 });
	await page.mouse.up();
	await expect.poll(() => legRequests.length).toBe(4);
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok', { timeout: 15_000 });

	// Undo restores the previous legs from the cache, without requests.
	await page.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok');
	await page.getByRole('button', { name: 'Umkehren' }).click();
	await expect(legs.nth(1)).toHaveAttribute('data-state', 'ok');
	expect(legRequests).toHaveLength(4);
});

test('planning needs an account', async ({ page }) => {
	await page.goto('/plan');
	await expect(page.getByTestId('planner-panel')).toContainText('Melde dich an');
});
