import { baseLocale, locales, type Locale } from '#lib/paraglide/runtime.js';

/**
 * The language an address names: /en/…, /fr/…, /it/…. German addresses have
 * no prefix and name none, so the cookie or the browser decides there.
 */
export function prefixLocale(pathname: string): Locale | undefined {
	const first = pathname.split('/')[1];
	return locales.find((l) => l !== baseLocale && l === first);
}
