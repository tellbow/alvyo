import { expect, test } from './fixtures';

test('light or dark follows the system unless chosen, and the choice stays', async ({
	browser
}) => {
	const context = await browser.newContext({ colorScheme: 'dark' });
	const page = await context.newPage();
	const ground = () =>
		page.evaluate(() => getComputedStyle(document.querySelector('.bg-ground')!).backgroundColor);
	await page.goto('/about');
	await expect(page.getByTestId('theme')).toHaveValue('system');
	expect(await ground()).toBe('rgb(14, 21, 18)');

	await page.getByTestId('theme').selectOption('light');
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
	expect(await ground()).toBe('rgb(242, 244, 239)');
	// Rendered so by the server: no flash of the dark page.
	await page.reload();
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
	await expect(page.getByTestId('theme')).toHaveValue('light');
	expect(await ground()).toBe('rgb(242, 244, 239)');

	await page.getByTestId('theme').selectOption('system');
	await page.reload();
	await expect(page.locator('html')).toHaveAttribute('data-theme', '');
	expect(await ground()).toBe('rgb(14, 21, 18)');
	await context.close();
});

test('dark chosen on a light system', async ({ browser }) => {
	const context = await browser.newContext({ colorScheme: 'light' });
	const page = await context.newPage();
	await page.goto('/about');
	await page.getByTestId('theme').selectOption('dark');
	await page.reload();
	expect(
		await page.evaluate(
			() => getComputedStyle(document.querySelector('.bg-ground')!).backgroundColor
		)
	).toBe('rgb(14, 21, 18)');
	await context.close();
});
