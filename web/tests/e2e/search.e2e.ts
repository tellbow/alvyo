import { signUp } from './accounts';
import { expect, test } from './fixtures';

test('find start and destination by name, then order and remove points', async ({ page }) => {
	const id = `find${Date.now().toString(36)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Finder',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);

	await page.goto('/plan');
	const points = page.getByTestId('points');
	await points.getByLabel('Start suchen …').fill('Gitschenen');
	await points
		.getByRole('option', { name: /^Gitschenen/ })
		.first()
		.click();
	await expect(points.getByTestId('point')).toHaveCount(1);
	await expect(points.getByTestId('point')).toContainText('Gitschenen');

	await points.getByLabel('Ziel suchen …').fill('Brisenhaus');
	await points.getByRole('option', { name: /Brisenhaus.*Hütte/ }).click();
	const legs = page.getByTestId('leg');
	await expect(legs).toHaveCount(1);
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok', { timeout: 30_000 });

	// A point from the map is added as the new destination; ↑ makes it an
	// intermediate point.
	const box = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
	await page.mouse.click(box.x + 60, box.y + 60);
	const names = points.getByTestId('point');
	await expect(names).toHaveCount(3);
	await expect(names.nth(2)).toContainText('Punkt auf der Karte');
	await names.nth(2).getByRole('button', { name: 'Nach oben' }).click();
	await expect(names.nth(1)).toContainText('Punkt auf der Karte');
	await expect(names.nth(2)).toContainText('Brisenhaus');
	await expect(legs).toHaveCount(2);
	await expect(legs.nth(1)).toHaveAttribute('data-state', /ok|error/, { timeout: 30_000 });
	await page.screenshot({ path: 'test-results/search.png' });

	// Removing it joins start and destination again, from the cache.
	await names.nth(1).getByRole('button', { name: 'Entfernen' }).click();
	await expect(legs).toHaveCount(1);
	await expect(legs.nth(0)).toHaveAttribute('data-state', 'ok');

	// The names are saved with the route.
	const panel = page.getByTestId('save-panel');
	await panel.getByLabel('Titel').fill('Gitschenen – Brisenhaus');
	await panel.getByRole('button', { name: 'Speichern' }).click();
	await expect(page).toHaveURL(/\/plan\/[0-9a-f-]{36}$/);
	await page.reload();
	await expect(points.getByTestId('point').nth(0)).toContainText('Gitschenen');
	await expect(points.getByTestId('point').nth(1)).toContainText('Brisenhaus');
});
