import { describe, expect, it } from 'vitest';
import { inPeriod, periodDay, ruleText } from './areas';

describe('protected areas', () => {
	it('knows whether a day is in a period over the new year', () => {
		const winter = { from: '12-01', to: '04-20' };
		expect(inPeriod(winter, '2026-12-01')).toBe(true);
		expect(inPeriod(winter, '2027-01-15')).toBe(true);
		expect(inPeriod(winter, '2027-04-21')).toBe(false);
		expect(inPeriod(winter, new Date(2026, 7, 1))).toBe(false);
		expect(inPeriod({ from: '05-01', to: '07-15' }, '2026-06-01')).toBe(true);
	});

	it('names days and rules in the page language', () => {
		expect(periodDay('12-01', 'de-CH')).toMatch(/^1\. Dez/);
		const a = {
			kind: 'hunting_reserve',
			id: '1',
			name: 'Schwarzhorn',
			binding: true,
			rule: { de: 'Teilschutz', fr: 'Protection partielle', it: 'Protezione parziale' }
		} as const;
		expect(ruleText(a, 'fr')).toBe('Protection partielle');
		expect(ruleText(a, 'en')).toBe('Teilschutz');
	});
});
