import { getLocale } from '$lib/paraglide/runtime';

/** The Intl locale for dates and numbers in the current language. */
export function intlLocale(): string {
	return { de: 'de-CH', en: 'en-GB', fr: 'fr-CH', it: 'it-CH' }[getLocale()] ?? 'de-CH';
}
