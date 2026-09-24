import type { ProtectedArea } from '$lib/api/client';

type Period = NonNullable<ProtectedArea['period']>;

/** Whether the day (YYYY-MM-DD, or a Date) lies in the period; it may wrap over the new year. */
export function inPeriod(p: Period, day: string | Date): boolean {
	const d =
		typeof day === 'string'
			? day.slice(5, 10)
			: `${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
	return p.from <= p.to ? d >= p.from && d <= p.to : d >= p.from || d <= p.to;
}

/** A period's day, «1. Dez.» in German. */
export function periodDay(mmdd: string, locale: string): string {
	const [m, d] = mmdd.split('-').map(Number);
	return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }).format(
		new Date(2001, m - 1, d)
	);
}

/** The rule in the page's language (English falls back to German). */
export function ruleText(a: ProtectedArea, lang: string): string {
	const r = a.rule;
	return (
		(lang === 'fr' ? r.fr : lang === 'it' ? r.it : lang === 'en' ? r.en || r.de : r.de) || r.de
	);
}
