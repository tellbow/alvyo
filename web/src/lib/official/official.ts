import type { Official } from '#lib/api/client.js';
import { m } from '#lib/paraglide/messages.js';

// SchweizMobil's own path per language (fr and it redirect from the German
// one, but land on their own).
const PATHS: Record<string, string> = {
	de: 'de/wanderland/route-',
	en: 'en/hiking-in-switzerland/route-',
	fr: 'fr/suisse-a-pied/itineraire-',
	it: 'it/svizzera-a-piedi/percorso-'
};

/** The route's page on SchweizMobil, in the language of the page. */
export function schweizMobilUrl(number: string, locale: string): string {
	return `https://schweizmobil.ch/${PATHS[locale] ?? PATHS.de}${encodeURIComponent(number)}`;
}

/** «Nationale Route 1», «Lokale Route 104» … */
export function officialLabel(o: Official): string {
	const label = {
		national: m.official_national,
		regional: m.official_regional,
		local: m.official_local,
		handicap: m.official_handicap
	}[o.kind];
	return label({ number: o.number });
}
