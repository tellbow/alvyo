import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

// The terrain's slope along a route (feedback issue 61): the test API has no
// swissALTI3D, so its answer is stubbed.
test('steep terrain shows as a band under the profile and in the overview', async ({ page }) => {
	const s = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `steep${s}@example.ch`,
			username: `steep${s}`,
			display_name: 'Steep',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Grat', ...routeContent(8.04, 46.665) }
	});
	const id = (await res.json()).id as string;
	await page.route('**/api/v1/routes/*/steepness*', (r) =>
		r.fulfill({
			json: {
				known: true,
				steep_m: 2100,
				stretches: [
					{ from_m: 100, to_m: 300, class: 1 },
					{ from_m: 300, to_m: 500, class: 3 }
				]
			}
		})
	);
	await page.goto(`/routes/${id}`);
	await expect(page.getByTestId('steep-along')).toContainText('2.1 km im Gelände steiler als 30°');
	await expect(page.getByTestId('steep-band')).toHaveCount(2);
});
