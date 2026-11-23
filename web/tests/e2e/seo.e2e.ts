import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('search engines: titles, one address per page, private pages left out, sitemap', async ({
	page,
	request
}) => {
	const id = `seo${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const email = `${id}@example.ch`;
	await signUp(page.request, {
		data: { email, username: id, display_name: 'Sina Search', password: 'sehr-geheim-123' }
	});
	const create = async (path: string, data: object) =>
		(await (await page.request.post(path, { data })).json()) as {
			id: string;
			share_token?: string;
		};
	const route = await create('/api/v1/routes', {
		title: `Gratweg ${id}`,
		visibility: 'public',
		...routeContent(8.04, 46.665)
	});
	const unlisted = await create('/api/v1/routes', {
		title: `Geheimtipp ${id}`,
		visibility: 'unlisted',
		...routeContent(8.04, 46.665)
	});
	const journey = await create('/api/v1/journeys', {
		title: `Via ${id}`,
		visibility: 'public',
		description: 'Drei Tage über die Pässe.'
	});
	const withStage = await (
		await page.request.post(`/api/v1/journeys/${journey.id}/stages`, { data: {} })
	).json();
	await page.request.post(
		`/api/v1/journeys/${journey.id}/stages/${withStage.stage_list[0].id}/route`,
		{ data: routeContent(8.05, 46.665) }
	);

	// As a search engine sees them: without a session.
	const head = async (path: string) => {
		const res = await request.get(path);
		expect(res.status()).toBe(200);
		const html = await res.text();
		return {
			html,
			title: html.match(/<title>([^<]*)<\/title>/)?.[1],
			description: html.match(/<meta name="description" content="([^"]*)"/)?.[1],
			canonical: html.match(/<link rel="canonical" href="([^"]*)"/)?.[1],
			noindex: html.includes('<meta name="robots" content="noindex"')
		};
	};

	const home = await head('/');
	expect(home.title).toBe('Alvyo – Wanderungen in der Schweiz planen und teilen');
	expect(home.description).toContain('swisstopo');
	expect(home.canonical).toMatch(/^http:\/\/[^/]+\/$/);

	// Filters in the address are not another page.
	expect((await head('/discover?bbox=7.9,46.5,8.2,46.8')).canonical).toMatch(/\/discover$/);

	const r = await head(`/routes/${route.id}`);
	// The main canton the route crosses is in its title and linked to its page.
	expect(r.title).toBe(`Gratweg ${id} – Wanderung, Bern · Alvyo`);
	expect(r.html).toMatch(/href="[^"]*cantons\/be"/);
	expect(r.description).toMatch(/^Wanderung: .* m · /);
	expect(r.canonical).toMatch(new RegExp(`/routes/${route.id}$`));
	expect(r.noindex).toBe(false);

	// The canton's page lists the route; a canton without public routes is
	// left out, an unknown one is not there.
	const be = await head('/cantons/be');
	expect(be.title).toBe('Wanderungen im Kanton Bern · Alvyo');
	expect(be.noindex).toBe(false);
	expect(be.html).toContain(`Gratweg ${id}`);
	expect((await request.get('/cantons/xx')).status()).toBe(404);

	const j = await head(`/journeys/${journey.id}`);
	expect(j.description).toMatch(/^Etappentour in 1 Etappen: .*Drei Tage über die Pässe\.$/);
	expect(j.canonical).toMatch(new RegExp(`/journeys/${journey.id}$`));
	// Link previews show the journey's stages on the map.
	const ogImage = j.html.match(/<meta property="og:image" content="([^"]*)"/)?.[1];
	expect(ogImage).toMatch(new RegExp(`/api/v1/journeys/${journey.id}/og\\.png\\?v=\\d+$`));
	const image = await request.get(ogImage!);
	expect(image.status()).toBe(200);
	expect(image.headers()['content-type']).toBe('image/png');

	// Every language has its own address, and each names the others.
	const en = await head(`/en/journeys/${journey.id}`);
	expect(en.html).toContain('<html lang="en"');
	expect(en.description).toMatch(/^Multi-day journey in 1 stages: /);
	expect(en.canonical).toMatch(new RegExp(`/en/journeys/${journey.id}$`));
	for (const [lang, prefix] of [
		['de', ''],
		['fr', '/fr'],
		['x-default', '']
	]) {
		expect(en.html).toMatch(
			new RegExp(
				`<link rel="alternate" hreflang="${lang}" href="http://[^/]+${prefix}/journeys/${journey.id}"`
			)
		);
	}

	// A share link and the pages of an account are not for search engines.
	const shared = await head(`/routes/${unlisted.id}?t=${unlisted.share_token}`);
	expect(shared.noindex).toBe(true);
	expect(shared.canonical).toBeUndefined();
	expect((await head('/login')).noindex).toBe(true);

	const robots = await (await request.get('/robots.txt')).text();
	expect(robots).toMatch(/^Sitemap: http:\/\/[^/]+\/sitemap\.xml$/m);
	const sitemap = await request.get('/sitemap.xml');
	expect(sitemap.headers()['content-type']).toBe('application/xml');
	const xml = await sitemap.text();
	for (const path of [
		`/routes/${route.id}`,
		`/it/journeys/${journey.id}`,
		`/fr/u/${id}`,
		'/cantons/be'
	]) {
		expect(xml).toContain(`${path}</loc>`);
	}
	expect(xml).not.toContain(unlisted.id);
});
