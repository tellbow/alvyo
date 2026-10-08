import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { leg } from './legs';

// On the way from Corviglia to Chamanna Jenatsch: «Wandern» goes round
// 250 m of T4 (16.7 km), «Alpinwandern» takes them (1.1 km).
test('a leg much longer by hiking offers the alpine way', async ({ page }) => {
	const id = `alp${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planer',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	// As saved after planning with «Wandern»: the leg knows the alpine way.
	const from = [9.76087, 46.50887, 2640];
	const to = [9.7498, 46.50993, 2690];
	const hiked = { ...leg([from, to]), alpine: { distance_m: 1115, sac_grade: 4 } };
	const created = await page.request.post('/api/v1/routes', {
		data: {
			title: 'Zur Jenatsch',
			visibility: 'private',
			profile: 'hike',
			anchors: [
				{ lon: from[0], lat: from[1] },
				{ lon: to[0], lat: to[1] }
			],
			legs: [hiked]
		}
	});
	expect(created.status()).toBe(201);
	const { id: routeId } = await created.json();

	await page.goto(`/plan/${routeId}`);
	const hint = page.getByTestId('leg-alpine');
	await expect(hint).toContainText(/Mit «Alpinwandern» nur 1\.1\skm statt/);
	await expect(hint).toContainText('Der kürzere Weg führt über T4.');
	await hint.getByRole('button', { name: 'Diesen Abschnitt alpin planen' }).click();

	// Routed with the alpine profile, along the trail.
	const leg0 = page.getByTestId('leg').first();
	await expect(leg0).toHaveAttribute('data-state', 'ok', { timeout: 30_000 });
	await expect(page.getByTestId('leg-alpine-used')).toHaveText(/Mit «Alpinwandern» geplant\./);
	await expect(leg0).toContainText(/^1\s+1\.1\skm/);
	await page
		.getByTestId('leg-alpine-used')
		.getByRole('button', { name: 'Wieder als Wanderung' })
		.click();
	await expect(page.getByTestId('leg-alpine')).toBeVisible({ timeout: 30_000 });
});
