import { signUp } from './accounts';
import { expect, test } from './fixtures';

// A long name in the longest language: nothing overlaps, links on one line.
test('the header fits at every width of the full navigation', async ({ browser }) => {
	const s = Date.now().toString(36);
	const login = await browser.newContext();
	const name = `long_name_of_thirty_${s}`.slice(0, 30);
	await signUp(login.request, {
		data: {
			email: `${name}@example.test`,
			username: name,
			display_name: 'Lang',
			password: 'sehr-geheim-123',
			locale: 'de'
		}
	});
	const storageState = await login.storageState();
	await login.close();

	for (const locale of ['de-CH', 'fr-CH', 'it-CH', 'en-GB']) {
		const context = await browser.newContext({ locale, storageState });
		const page = await context.newPage();
		await page.goto('/about');
		for (const width of [1280, 1359, 1360, 1440, 1535, 1536]) {
			await page.setViewportSize({ width, height: 720 });
			const parts = await page.evaluate(() =>
				[...document.querySelectorAll('header > *')]
					.filter((e) => getComputedStyle(e).display !== 'none')
					.map((e) => {
						const r = e.getBoundingClientRect();
						return { left: r.left, right: r.right, height: r.height };
					})
			);
			const at = `${locale} at ${width}`;
			for (let i = 1; i < parts.length; i++) {
				expect(parts[i].left, `${at}: part ${i} overlaps`).toBeGreaterThanOrEqual(
					parts[i - 1].right
				);
			}
			expect(parts.at(-1)!.right, `${at}: past the edge`).toBeLessThanOrEqual(width);
			const nav = page.locator('header > nav');
			if (width >= 1360) {
				await expect(nav, at).toBeVisible();
				// One line of links in its pill.
				expect((await nav.boundingBox())!.height, `${at}: links wrap`).toBeLessThan(48);
				expect(
					(await page.getByTestId('current-user').first().boundingBox())!.width,
					`${at}: no room for the name`
				).toBeGreaterThan(40);
			} else {
				await expect(nav, at).toBeHidden();
			}
		}
		await context.close();
	}
});
