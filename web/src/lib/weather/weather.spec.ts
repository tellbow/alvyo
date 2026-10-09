import { describe, expect, it } from 'vitest';
import { WEATHER_ICONS, climateText, dayLabel, dayText, weatherSymbol } from './weather';

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

	it('rounds a little below zero to 0, not -0', () => {
		expect(dayText({ ...day, min_c: -0.4, max_c: 6.2 }, 'de-CH')).toMatch(/^0–6\s°C · /);
		const c = {
			month: 1,
			station: 'Säntis',
			height: 2502,
			rain_station: 'Säntis',
			min_c: -0.3,
			max_c: 0.2,
			rain_mm: 200,
			rain_days: 15
		};
		expect(climateText(c, 2026, 'de-CH')).toContain('Januar: 0–0 °C');
	});

	it('names the day', () => {
		expect(dayLabel('2026-09-29', 'de-CH')).toBe('Di., 29.9.');
	});

	it("gives MeteoSwiss's symbols our icons and their words", () => {
		expect(weatherSymbol(1, 'de')).toEqual({ icon: 'sun', text: 'sonnig' });
		expect(weatherSymbol(20, 'fr')).toEqual({ icon: 'rain', text: 'très nuageux, pluie continue' });
		expect(weatherSymbol(128, 'en')).toEqual({ icon: 'fog', text: 'fog' }); // the night's fog
		expect(weatherSymbol(undefined)).toBeUndefined();
		expect(weatherSymbol(0)).toBeUndefined();
		for (let code = 1; code <= 42; code++) {
			const s = weatherSymbol(code, 'it')!;
			expect(WEATHER_ICONS[s.icon], String(code)).toBeDefined();
			expect(s.text).not.toBe('');
		}
	});

	it('says what is usual in a month', () => {
		const c = {
			month: 10,
			station: 'Interlaken',
			height: 578,
			rain_station: 'Grindelwald',
			min_c: 3,
			max_c: 11.1,
			rain_mm: 102.4,
			rain_days: 9.9
		};
		expect(climateText(c, 2026, 'de-CH')).toBe(
			'Üblich im Oktober: 3–11 °C, an 10 von 31 Tagen Regen, 102 mm im Monat'
		);
		expect(climateText({ ...c, month: 2 }, 2028, 'de-CH')).toContain('von 29 Tagen');
	});
});
