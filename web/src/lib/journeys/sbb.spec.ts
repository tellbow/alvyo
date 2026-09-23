import { describe, expect, it } from 'vitest';
import { sbbTimetableUrl } from './sbb';

describe('sbbTimetableUrl', () => {
	it('links the journey to a stage start on its date', () => {
		const url = new URL(
			sbbTimetableUrl({ to: 'Weisstannen, Oberdorf', date: '2026-07-04', locale: 'de' })
		);
		expect(url.origin + url.pathname).toBe(
			'https://www.sbb.ch/de/kaufen/pages/fahrplan/fahrplan.xhtml'
		);
		expect(url.searchParams.get('nach')).toBe('Weisstannen, Oberdorf');
		expect(url.searchParams.get('datum')).toBe('04.07.2026');
		expect(url.searchParams.has('von')).toBe(false);
		expect(url.searchParams.has('suche')).toBe(false);
	});

	it('searches right away when both ends are known', () => {
		const url = new URL(sbbTimetableUrl({ from: 'Elm, Station', to: 'Zürich HB', locale: 'en' }));
		expect(url.pathname).toBe('/en/buying/pages/fahrplan/fahrplan.xhtml');
		expect(url.searchParams.get('von')).toBe('Elm, Station');
		expect(url.searchParams.get('suche')).toBe('true');
		expect(url.searchParams.has('datum')).toBe(false);
	});
});
