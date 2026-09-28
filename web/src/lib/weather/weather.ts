import type { ForecastDay } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';
import { intlLocale } from '$lib/util/locale';

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
