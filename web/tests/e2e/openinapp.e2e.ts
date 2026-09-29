import { expect, test } from './fixtures';
import { routeContent } from './legs';

test.describe('on an iPhone', () => {
	test.use({
		userAgent:
			'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
	});

	test("a route opens in the app, with the link's token", async ({ page }) => {
		const id = `app${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
		await page.request.post('/api/v1/auth/signup', {
			data: {
				email: `${id}@example.ch`,
				username: id,
				display_name: 'App',
				password: 'sehr-geheim-123'
			}
		});
		const res = await page.request.post('/api/v1/routes', {
			data: { title: 'Per Link', visibility: 'private', ...routeContent(9.34, 46.99) }
		});
		const route = await res.json();
		await page.goto(`/routes/${route.id}`);
		await expect(page.getByTestId('open-in-app')).toHaveAttribute(
			'href',
			`alvyo://open/routes/${route.id}`
		);
		// A shared link's token rides along.
		await page.goto(`/routes/${route.id}?t=tok`);
		await expect(page.getByTestId('open-in-app')).toHaveAttribute(
			'href',
			`alvyo://open/routes/${route.id}?t=tok`
		);
	});
});

test('not on a computer', async ({ page }) => {
	await page.goto('/discover');
	await expect(page.getByTestId('open-in-app')).toHaveCount(0);
});
