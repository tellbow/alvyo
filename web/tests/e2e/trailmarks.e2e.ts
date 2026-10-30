import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

// «Wanderwegnetz» shows the trails' markings, not dots (feedback issue 71).
test('the trail breakdown shows the trail markings', async ({ page }) => {
	const s = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const res = await signUp(page.request, {
		data: {
			email: `mark${s}@example.ch`,
			username: `mark${s}`,
			display_name: 'M',
			password: 'sehr-geheim-123'
		}
	});
	expect(res.status()).toBe(200);
	const route = await (
		await page.request.post('/api/v1/routes', {
			data: { title: `Markierung ${s}`, ...routeContent(8.05, 46.665) }
		})
	).json();
	await page.goto(`/routes/${route.id}`);
	const trail = page.getByTestId('breakdowns').locator('section').first();
	await expect(trail).toContainText('Wanderwegnetz');
	await expect(trail.locator('svg').first()).toBeVisible();
});
