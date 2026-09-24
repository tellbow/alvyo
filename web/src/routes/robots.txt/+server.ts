import type { RequestHandler } from './$types';

// Pages that are not public say so themselves (noindex); crawlers may read
// everything, link previews included.
export const GET: RequestHandler = ({ url }) =>
	new Response(`User-agent: *\nDisallow:\n\nSitemap: ${url.origin}/sitemap.xml\n`, {
		headers: {
			'content-type': 'text/plain; charset=utf-8',
			'cache-control': 'public, max-age=86400'
		}
	});
