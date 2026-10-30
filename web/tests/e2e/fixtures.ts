import {
	expect,
	test as base,
	type Browser,
	type BrowserContext,
	type Page,
	type Response
} from '@playwright/test';

const hydrating = new WeakSet<BrowserContext>();

/**
 * After goto() and reload(), our pages wait until they are hydrated: a fill
 * or click before Svelte attaches its handlers does nothing (a search not
 * searched, a confirmation not opened), which made tests fail now and then.
 * The root layout enables the language menu once hydrated; the admin
 * portal's frame marks itself.
 */
function waitForHydration(context: BrowserContext, origin: string) {
	if (hydrating.has(context)) return;
	hydrating.add(context);
	context.on('page', (page) => {
		for (const name of ['goto', 'reload'] as const) {
			const navigate = page[name].bind(page) as (...args: unknown[]) => Promise<Response | null>;
			(page as unknown as Record<string, unknown>)[name] = async (...args: unknown[]) => {
				const response = await navigate(...args);
				if (isOurPage(page, response, origin)) {
					await expect(
						page
							.locator(
								'[data-testid="language"]:enabled, [data-testid="admin-frame"][data-hydrated]'
							)
							.first()
					).toBeAttached({ timeout: 15_000 });
				}
				return response;
			};
		}
	});
}

/** An HTML page of the web app, not the API, a file or the fake identity provider. */
function isOurPage(page: Page, response: Response | null, origin: string): boolean {
	const type = response?.headers()['content-type'] ?? '';
	return new URL(page.url()).origin === origin && type.startsWith('text/html');
}

/**
 * Every end-to-end test fails if the page throws an uncaught error or logs a
 * console error (e.g. Svelte's effect_update_depth_exceeded), even when the
 * page still looks fine.
 */
export const test = base.extend<{ pageErrors: string[] }, { hydrating: Browser }>({
	// Contexts a test opens itself (a second user) wait for hydration too.
	hydrating: [
		async ({ browser }, use, workerInfo) => {
			const origin = new URL(String(workerInfo.project.use.baseURL)).origin;
			const newContext = browser.newContext.bind(browser);
			browser.newContext = async (...args) => {
				const context = await newContext(...args);
				waitForHydration(context, origin);
				return context;
			};
			await use(browser);
		},
		{ scope: 'worker', auto: true }
	],
	pageErrors: [
		async ({ context, baseURL }, use) => {
			waitForHydration(context, new URL(String(baseURL)).origin);
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
