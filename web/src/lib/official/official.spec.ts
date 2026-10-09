import { describe, expect, it } from 'vitest';
import { officialLabel, schweizMobilUrl } from './official';

describe('official routes', () => {
	it('links the route on SchweizMobil in the language of the page', () => {
		expect(schweizMobilUrl('1', 'de')).toBe('https://schweizmobil.ch/de/wanderland/route-1');
		expect(schweizMobilUrl('104', 'fr')).toBe(
			'https://schweizmobil.ch/fr/suisse-a-pied/itineraire-104'
		);
		expect(schweizMobilUrl('7', 'it')).toBe(
			'https://schweizmobil.ch/it/svizzera-a-piedi/percorso-7'
		);
		expect(schweizMobilUrl('7', 'en')).toBe(
			'https://schweizmobil.ch/en/hiking-in-switzerland/route-7'
		);
		expect(schweizMobilUrl('7', 'rm')).toBe('https://schweizmobil.ch/de/wanderland/route-7');
	});

	it('names the kind and number', () => {
		expect(officialLabel({ number: '1', kind: 'national' })).toBe('Nationale Route 1');
		expect(officialLabel({ number: '145', kind: 'handicap' })).toBe('Hindernisfreie Route 145');
	});
});
