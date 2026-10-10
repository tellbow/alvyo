import type { Notice, ProtectedArea } from '#lib/api/client.js';

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

type Texts = Notice['title'];

/** A text in the page's language (German where it has none). */
export function noticeText(t: Texts, lang: string): string {
	return (
		((lang === 'fr' ? t.fr : lang === 'it' ? t.it : lang === 'en' ? t.en : t.de) || t.de) ?? ''
	);
}

/** A day (YYYY-MM-DD) as «29. Sept.» in German. */
export function shootingDay(day: string, locale: string): string {
	return new Intl.DateTimeFormat(locale, {
		day: 'numeric',
		month: 'short',
		timeZone: 'UTC'
	}).format(new Date(`${day}T00:00:00Z`));
}

/** Whether a notice concerns one of the days (YYYY-MM-DD). */
export function touches(n: Notice, days: string[]): boolean {
	if (n.kind === 'shooting') return (n.days ?? []).some((d) => days.includes(d.date));
	return days.some((d) => (!n.from || d >= n.from) && (!n.to || d <= n.to));
}
