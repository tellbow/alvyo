import { error } from '@sveltejs/kit';
import { api } from '$lib/api/client';
import { locales, localizeUrl } from '$lib/paraglide/runtime';
import type { RequestHandler } from './$types';

const PATHS = {
	route: '/routes/',
	journey: '/journeys/',
	collection: '/collections/',
	profile: '/u/'
} as const;

/**
 * The public pages in every language: the start, discover and about pages,
 * and every public item.
 */
export const GET: RequestHandler = async ({ fetch, url }) => {
	const { data } = await api(fetch, url.origin).GET('/sitemap');
	if (!data) error(503);
	const pages: string[] = [];
	const add = (path: string, lastmod?: string) => {
		for (const locale of locales) {
			const loc = escape(localizeUrl(new URL(path, url.origin), { locale }).href);
			pages.push(`<url><loc>${loc}</loc>${lastmod ? `<lastmod>${lastmod}</lastmod>` : ''}</url>`);
		}
	};
	for (const p of ['/', '/discover', '/about']) add(p);
	for (const e of data.entries) {
		add(PATHS[e.kind] + encodeURIComponent(e.id), e.updated_at.slice(0, 10));
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
