import { describe, expect, it } from 'vitest';
import { cantonName, isCanton } from './cantons';

describe('cantonName', () => {
	it('names the canton in each language', () => {
		expect(cantonName('GR', 'de')).toBe('Graubünden');
		expect(cantonName('GR', 'en')).toBe('Grisons');
		expect(cantonName('GR', 'fr')).toBe('Grisons');
		expect(cantonName('GR', 'it')).toBe('Grigioni');
	});

	it('keeps an unknown code as it is', () => {
		expect(cantonName('FL', 'de')).toBe('FL');
	});
});

describe('isCanton', () => {
	it('knows the 26 cantons and nothing else', () => {
		const codes = 'AG AI AR BE BL BS FR GE GL GR JU LU NE NW OW SG SH SO SZ TG TI UR VD VS ZG ZH';
		expect(codes.split(' ').every(isCanton)).toBe(true);
		expect(isCanton('be')).toBe(false);
		expect(isCanton('FL')).toBe(false);
	});
});
