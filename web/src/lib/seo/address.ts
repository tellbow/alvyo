import { localizeUrl, type Locale } from '#lib/paraglide/runtime.js';

/**
 * A page's address in a language as it is served: German without a prefix,
 * the other languages' start pages without the trailing slash (/fr, not
 * /fr/, which SvelteKit redirects): search engines get no redirects.
 */
export function pageAddress(path: URL, locale: Locale): string {
	const u = localizeUrl(path, { locale });
	if (u.pathname.length > 1 && u.pathname.endsWith('/')) u.pathname = u.pathname.slice(0, -1);
	return u.href;
}
