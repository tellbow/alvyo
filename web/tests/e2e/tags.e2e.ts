import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('tag two routes and filter the list by a tag', async ({ page }) => {
	const id = `tags${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Tagger',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	const ids: string[] = [];
	for (const [title, lon] of [
		['Gratweg', 8.04],
		['Seeweg', 8.05],
		['Talweg', 8.06]
	] as const) {
		const res = await page.request.post('/api/v1/routes', {
			data: { title, ...routeContent(lon, 46.665) }
		});
		expect(res.status()).toBe(201);
		ids.push((await res.json()).id);
	}

	// Tags are typed in the route editor and saved with the route.
	for (const [i, tags] of [
		[0, ['Winter', 'Tessin']],
		[1, ['winter']]
	] as const) {
		await page.goto(`/plan/${ids[i]}`);
		// The map is up once the page runs: typed tags reach the field's handlers.
		await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
		const input = page.getByTestId('save-panel').getByLabel('Tags');
		for (const t of tags) {
			await input.fill(t);
			await input.press('Enter');
		}
		await expect(page.getByTestId('save-panel').getByTestId('tag')).toHaveCount(tags.length);
		await page.getByRole('button', { name: 'Speichern' }).click();
		await expect(page.getByTestId('planner-panel').getByRole('status')).toHaveText('Gespeichert');
	}

	await page.goto('/routes');
	const rows = page.getByTestId('route-list').locator(':scope > li');
	await expect(rows).toHaveCount(3);
	// A click on a tag filters the list, ignoring case.
	await rows.filter({ hasText: 'Gratweg' }).getByRole('link', { name: 'Winter' }).click();
	await expect(page).toHaveURL(/\?tag=Winter$/);
	await expect(page.getByTestId('tag-filter')).toContainText('Winter');
	await expect(rows).toHaveCount(2);
	await expect(rows.filter({ hasText: 'Talweg' })).toHaveCount(0);

	await page.getByRole('link', { name: 'Alle zeigen' }).click();
	await expect(rows).toHaveCount(3);
	await rows.filter({ hasText: 'Gratweg' }).getByRole('link', { name: 'Tessin' }).click();
	await expect(rows).toHaveCount(1);

	// The row still opens the route.
	await rows.first().getByRole('link', { name: 'Gratweg' }).click();
	await expect(page.getByTestId('route-title')).toHaveText('Gratweg');
	await expect(page.getByTestId('tags')).toContainText('Tessin');
});
