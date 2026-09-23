import { expect, test as base } from '@playwright/test';

/**
 * Every end-to-end test fails if the page throws an uncaught error or logs a
 * console error (e.g. Svelte's effect_update_depth_exceeded), even when the
 * page still looks fine.
 */
export const test = base.extend<{ pageErrors: string[] }>({
	pageErrors: [
		async ({ context }, use) => {
			const errors: string[] = [];
			context.on('page', (page) => {
				page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
				page.on('console', (m) => {
					// Failed requests we trigger on purpose (401, 404 …) are not bugs,
					// nor is the tile cache's per-IP limit (503), which parallel test
					// workers share.
					const text = m.text();
					if (
						m.type() === 'error' &&
						!text.startsWith('Failed to load resource') &&
						!/AJAXError: .*\(503\): \S+\/tiles\/wmts\//.test(text)
					) {
						errors.push(`console: ${text}`);
					}
				});
			});
			await use(errors);
			expect(errors, 'errors in the browser').toEqual([]);
		},
		{ auto: true }
	]
});

export { expect };
