import { error } from '@sveltejs/kit';
import { api } from '$lib/api/client';
import type { RequestHandler } from './$types';

const PATHS = {
	route: '/routes/',
	journey: '/journeys/',
	collection: '/collections/',
	profile: '/u/'
} as const;

/** The public pages: the start, discover and about pages, and every public item. */
export const GET: RequestHandler = async ({ fetch, url }) => {
	const { data } = await api(fetch, url.origin).GET('/sitemap');
	if (!data) error(503);
	const pages = ['/', '/discover', '/about'].map((p) => `<url><loc>${url.origin}${p}</loc></url>`);
	for (const e of data.entries) {
		const loc = escape(url.origin + PATHS[e.kind] + encodeURIComponent(e.id));
		pages.push(`<url><loc>${loc}</loc><lastmod>${e.updated_at.slice(0, 10)}</lastmod></url>`);
	}
	return new Response(
		'<?xml version="1.0" encoding="UTF-8"?>\n' +
			'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
			pages.join('\n') +
			'\n</urlset>\n',
		{ headers: { 'content-type': 'application/xml', 'cache-control': 'public, max-age=3600' } }
	);
};

function escape(s: string) {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/'/g, '&apos;');
}
