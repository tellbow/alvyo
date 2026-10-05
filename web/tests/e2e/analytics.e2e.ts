import { expect, test } from './fixtures';

// On the site (here faked: the flag app.html sets on alvyo.tellbow.ch), a
// page view carries the route's pattern and no secret of the address; the
// banner asks once.
test('page views without secrets, consent asked once', async ({ page }) => {
	await page.addInitScript(() => {
		(window as { alvyoAnalytics?: boolean }).alvyoAnalytics = true;
	});
	await page.goto('/friends/invite/geheim?t=auch-geheim');
	await expect(page.getByTestId('consent')).toBeVisible();
	const sets = () =>
		page.evaluate(() =>
			(window as unknown as { dataLayer: unknown[][] }).dataLayer
				.map((a) => Array.from(a))
				.filter((a) => a[0] === 'set')
				.map((a) => a[1])
		);
	await expect.poll(sets).toContainEqual({
		page_location: new URL('/friends/invite/-', page.url()).href,
		page_title: '/friends/invite/[token]'
	});
	expect(JSON.stringify(await sets())).not.toContain('geheim');

	await page.getByTestId('consent').getByRole('button', { name: 'Ablehnen' }).click();
	await page.reload();
	await expect(page.getByTestId('friend-invite')).toBeVisible();
	await expect(page.getByTestId('consent')).toHaveCount(0);
});
