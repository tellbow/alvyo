import { describe, expect, it } from 'vitest';
import { dayLabel, dayText } from './weather';

describe('weather', () => {
	const day = {
		date: '2026-09-29',
		min_c: 4.4,
		max_c: 12.6,
		rain_mm: 3.2,
		rain_lo_mm: 0.4,
		rain_hi_mm: 9.8
	};

	it('says temperatures and precipitation with its range, or dry', () => {
		expect(dayText(day, 'de-CH')).toBe('4–13 °C · 3.2 mm Niederschlag (0.4–9.8 mm)');
		expect(dayText({ ...day, rain_mm: 0, rain_lo_mm: 0, rain_hi_mm: 0.2 }, 'de-CH')).toBe(
			'4–13 °C · trocken'
		);
	});

	it('names the day', () => {
		expect(dayLabel('2026-09-29', 'de-CH')).toBe('Di., 29.9.');
	});
});
