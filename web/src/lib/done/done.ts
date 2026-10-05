import { intlLocale } from '$lib/util/locale';

/** A day (YYYY-MM-DD) as «1.8.2026», in the reader's language. */
export function doneDate(day: string, locale = intlLocale()): string {
	return new Intl.DateTimeFormat(locale, {
		day: 'numeric',
		month: 'numeric',
		year: 'numeric',
		timeZone: 'UTC'
	}).format(new Date(`${day}T00:00:00Z`));
}

export type DoneFilter = '' | 'done' | 'planned';

/** The status filter of a list or map page (`?done=`). */
export function readDone(p: URLSearchParams): DoneFilter {
	const v = p.get('done');
	return v === 'done' || v === 'planned' ? v : '';
}

/** Whether an item with this done day passes the filter. */
export function passes(filter: DoneFilter, doneOn: string | undefined): boolean {
	return filter === '' || (filter === 'done') === !!doneOn;
}
