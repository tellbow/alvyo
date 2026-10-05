import { expect, test } from './fixtures';

test('how far one gets: from a place, then from the map, on alpine ways', async ({
	page,
	context
}) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 12
			})
		);
	});
	const id = `reach${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Reacher',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	// From the planner's tabs.
	await page.goto('/plan');
	await page.getByTestId('plan-tab-reach').click();
	await expect(page).toHaveURL(/\/plan\/reach$/);
	const panel = page.getByTestId('reach-panel');

	await panel.getByLabel('Start suchen').fill('Gitschenen');
	await panel
		.getByRole('option', { name: /^Gitschenen/ })
		.first()
		.click();
	await expect(panel.getByTestId('reach-start')).toContainText('Gitschenen');
	const legend = panel.getByTestId('reach-legend');
	await expect(legend.getByRole('listitem')).toHaveText(
		['bis 2 Stunden', 'bis 4 Stunden', 'bis 8 Stunden'],
		{ timeout: 60_000 }
	);
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\broute-reach\b/);

	// A point on the map, then the alpine ways from there.
	const canvas = page.locator('canvas.maplibregl-canvas');
	const box = (await canvas.boundingBox())!;
	await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
	await expect(panel.getByTestId('reach-start')).not.toContainText('Gitschenen');
	const asked = page.waitForRequest(
		(r) => r.url().includes('/api/v1/routing/reach') && r.postDataJSON().profile === 'alpine'
	);
	await panel.getByTestId('reach-profile').selectOption('alpine');
	await asked;
	await expect(legend.getByRole('listitem')).toHaveCount(3, { timeout: 60_000 });
});
