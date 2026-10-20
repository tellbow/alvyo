import { describe, expect, it } from 'vitest';
import { inPeriod, noticeText, periodDay, roughly, ruleText, shootingDay, touches } from './areas';

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

describe('closures and shooting', () => {
	const closure = {
		kind: 'closure' as const,
		id: '1',
		title: { de: 'Seewäldli', fr: '', it: '', en: 'Lake wood' },
		from: '2026-09-01',
		to: '2026-10-31'
	};
	const shooting = {
		kind: 'shooting' as const,
		id: '2',
		title: { de: 'Geissalp', fr: '', it: '' },
		days: [{ date: '2026-09-29', from: '0800', to: '1700' }]
	};

	it('concerns a hike on its days only', () => {
		expect(touches(closure, ['2026-10-31'])).toBe(true);
		expect(touches(closure, ['2026-11-01'])).toBe(false);
		expect(touches(shooting, ['2026-09-28', '2026-09-29'])).toBe(true);
		expect(touches(shooting, ['2026-09-30'])).toBe(false);
	});

	it('speaks the page language, German where the text is missing', () => {
		expect(noticeText(closure.title, 'en')).toBe('Lake wood');
		expect(noticeText(closure.title, 'fr')).toBe('Seewäldli');
		expect(shootingDay('2026-09-29', 'de-CH')).toBe('29. Sept.');
	});
});

describe('snow along', () => {
	it('rounds lengths to 50 m, at least 50', () => {
		expect(roughly(1234)).toBe(1250);
		expect(roughly(1220)).toBe(1200);
		expect(roughly(10)).toBe(50);
	});
});
