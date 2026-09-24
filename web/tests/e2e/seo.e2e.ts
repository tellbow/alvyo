import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { linkFromMail } from './mailpit';

test('search engines: titles, one address per page, private pages left out, sitemap', async ({
	page,
	request
}) => {
	const id = `seo${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const email = `${id}@example.ch`;
	await page.request.post('/api/v1/auth/signup', {
		data: { email, username: id, display_name: 'Sina Search', password: 'sehr-geheim-123' }
	});
	const token = new URL(await linkFromMail(email, '/verify-email')).searchParams.get('token');
	await page.request.post('/api/v1/auth/verify-email', { data: { token } });
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

	// As a search engine sees them: without a session.
	const head = async (path: string) => {
		const res = await request.get(path);
		expect(res.status()).toBe(200);
		const html = await res.text();
		return {
			title: html.match(/<title>([^<]*)<\/title>/)?.[1],
			description: html.match(/<meta name="description" content="([^"]*)"/)?.[1],
			canonical: html.match(/<link rel="canonical" href="([^"]*)"/)?.[1],
			noindex: html.includes('<meta name="robots" content="noindex"')
		};
	};

	const home = await head('/');
	expect(home.title).toBe('odysgeh – Wanderungen in der Schweiz planen und teilen');
	expect(home.description).toContain('swisstopo');
	expect(home.canonical).toMatch(/^http:\/\/[^/]+\/$/);

	// Filters in the address are not another page.
	expect((await head('/discover?bbox=7.9,46.5,8.2,46.8')).canonical).toMatch(/\/discover$/);

	const r = await head(`/routes/${route.id}`);
	expect(r.title).toBe(`Gratweg ${id} · odysgeh`);
	expect(r.description).toMatch(/^Wanderung: .* m · /);
	expect(r.canonical).toMatch(new RegExp(`/routes/${route.id}$`));
	expect(r.noindex).toBe(false);

	const j = await head(`/journeys/${journey.id}`);
	expect(j.description).toMatch(/^Etappentour in 0 Etappen: .*Drei Tage über die Pässe\.$/);
	expect(j.canonical).toMatch(new RegExp(`/journeys/${journey.id}$`));

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
	for (const path of [`/routes/${route.id}`, `/journeys/${journey.id}`, `/u/${id}`]) {
		expect(xml).toContain(`${path}</loc>`);
	}
	expect(xml).not.toContain(unlisted.id);
});
