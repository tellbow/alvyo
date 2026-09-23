/**
 * Links into the SBB timetable. Format from SBB's "Deep Linking SBB
 * Fahrplan" v0.6 (2017), the latest public description: station names in
 * von/nach, datum as dd.MM.yyyy, zeit as HH:mm. Checked on sbb.ch on
 * 2026-09-23: von, nach, datum and suche=true are taken over.
 */
const BASE: Record<string, string> = {
	de: 'https://www.sbb.ch/de/kaufen/pages/fahrplan/fahrplan.xhtml',
	fr: 'https://www.sbb.ch/fr/acheter/pages/fahrplan/fahrplan.xhtml',
	it: 'https://www.sbb.ch/it/acquistare/pages/fahrplan/fahrplan.xhtml',
	en: 'https://www.sbb.ch/en/buying/pages/fahrplan/fahrplan.xhtml'
};

export function sbbTimetableUrl(opts: {
	from?: string;
	to?: string;
	/** YYYY-MM-DD */
	date?: string | null;
	locale: string;
}): string {
	const params = new URLSearchParams();
	if (opts.from) params.set('von', opts.from);
	if (opts.to) params.set('nach', opts.to);
	if (opts.date) {
		const [y, mo, d] = opts.date.split('-');
		params.set('datum', `${d}.${mo}.${y}`);
	}
	if (opts.from && opts.to) params.set('suche', 'true');
	return `${BASE[opts.locale] ?? BASE.de}?${params}`;
}
