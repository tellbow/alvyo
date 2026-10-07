import { describe, expect, it } from 'vitest';
import { pageAddress } from './address';

describe('pageAddress', () => {
	const at = (path: string) => new URL(path, 'https://alvyo.tellbow.ch');

	it('gives start pages without the trailing slash, which would be redirected', () => {
		expect(pageAddress(at('/'), 'de')).toBe('https://alvyo.tellbow.ch/');
		expect(pageAddress(at('/'), 'fr')).toBe('https://alvyo.tellbow.ch/fr');
		expect(pageAddress(at('/'), 'en')).toBe('https://alvyo.tellbow.ch/en');
	});

	it('prefixes other pages with the language, German without', () => {
		expect(pageAddress(at('/about'), 'de')).toBe('https://alvyo.tellbow.ch/about');
		expect(pageAddress(at('/about'), 'it')).toBe('https://alvyo.tellbow.ch/it/about');
	});
});
