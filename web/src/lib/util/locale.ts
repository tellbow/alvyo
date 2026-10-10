import { getLocale } from '#lib/paraglide/runtime.js';

/** The Intl locale for dates and numbers in the current language. */
export function intlLocale(): string {
	return { de: 'de-CH', en: 'en-GB', fr: 'fr-CH', it: 'it-CH' }[getLocale()] ?? 'de-CH';
}

/** When something was saved, in Swiss time («28.09.2026, 14:02»). */
export function savedAt(at: string): string {
	return new Intl.DateTimeFormat(intlLocale(), {
		dateStyle: 'medium',
		timeStyle: 'short',
		timeZone: 'Europe/Zurich'
	}).format(new Date(at));
}

/** The day a hike was made, in Swiss time («20.09.2026» in German). */
export function hikeDate(at: string): string {
	return new Intl.DateTimeFormat(intlLocale(), {
		dateStyle: 'medium',
		timeZone: 'Europe/Zurich'
	}).format(new Date(at));
}
