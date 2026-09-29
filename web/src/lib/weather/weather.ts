import type { Climate, ForecastDay } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';
import { getLocale } from '$lib/paraglide/runtime';
import { intlLocale } from '$lib/util/locale';
import table from './symbols.json';

export type WeatherIcon = keyof typeof table.icons;
type Lang = 'de' | 'fr' | 'it' | 'en';

/** Our icons (layers of colour and shape, 24 × 24), one for several of MeteoSwiss's symbols. */
export const WEATHER_ICONS = table.icons as Record<WeatherIcon, { color: string; path: string }[]>;

/**
 * MeteoSwiss's pictogram number (1–42; the night's 101–142 as the day's) as
 * our icon and MeteoSwiss's words for it; undefined for none.
 */
export function weatherSymbol(
	code: number | undefined,
	lang = getLocale() as Lang
): { icon: WeatherIcon; text: string } | undefined {
	const s = (table.symbols as Record<string, Record<Lang, string> & { icon: string }>)[
		String(code && code > 100 ? code - 100 : code)
	];
	return s && { icon: s.icon as WeatherIcon, text: s[lang] };
}

/** «Üblich im Oktober: 3–11 °C, an 10 von 31 Tagen Regen, 102 mm im Monat». */
export function climateText(c: Climate, year: number, locale = intlLocale()): string {
	const n = (x: number, digits = 0) =>
		new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(x);
	const month = new Intl.DateTimeFormat(locale, { month: 'long', timeZone: 'UTC' }).format(
		new Date(Date.UTC(year, c.month - 1, 1))
	);
	return m.weather_climate({
		month,
		min: n(Math.round(c.min_c)),
		max: n(Math.round(c.max_c)),
		days: n(Math.round(c.rain_days)),
		total: new Date(Date.UTC(year, c.month, 0)).getUTCDate(),
		mm: n(Math.round(c.rain_mm))
	});
}

const NBSP = ' ';

/** «4–12 °C · 3 mm Niederschlag (0–10 mm)», or «… · trocken». */
export function dayText(d: ForecastDay, locale = intlLocale()): string {
	const n = (x: number, digits = 0) =>
		new Intl.NumberFormat(locale, { maximumFractionDigits: digits }).format(x);
	const temp = `${n(Math.round(d.min_c))}–${n(Math.round(d.max_c))}${NBSP}°C`;
	const rain =
		d.rain_hi_mm < 0.5
			? m.weather_dry()
			: m.weather_rain({ mm: n(d.rain_mm, 1), lo: n(d.rain_lo_mm, 1), hi: n(d.rain_hi_mm, 1) });
	return `${temp} · ${rain}`;
}

/** A day (YYYY-MM-DD) as «Di 29.9.» in German. */
export function dayLabel(date: string, locale = intlLocale()): string {
	return new Intl.DateTimeFormat(locale, {
		weekday: 'short',
		day: 'numeric',
		month: 'numeric',
		timeZone: 'UTC'
	}).format(new Date(`${date}T00:00:00Z`));
}
