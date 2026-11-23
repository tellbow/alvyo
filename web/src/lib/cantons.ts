import type { Locale } from '#lib/paraglide/runtime.js';

/** The cantons' names by code, in German, English, French and Italian. */
const NAMES: Record<string, [string, string, string, string]> = {
	AG: ['Aargau', 'Aargau', 'Argovie', 'Argovia'],
	AI: [
		'Appenzell Innerrhoden',
		'Appenzell Innerrhoden',
		'Appenzell Rhodes-Intérieures',
		'Appenzello Interno'
	],
	AR: [
		'Appenzell Ausserrhoden',
		'Appenzell Ausserrhoden',
		'Appenzell Rhodes-Extérieures',
		'Appenzello Esterno'
	],
	BE: ['Bern', 'Bern', 'Berne', 'Berna'],
	BL: ['Basel-Landschaft', 'Basel-Landschaft', 'Bâle-Campagne', 'Basilea Campagna'],
	BS: ['Basel-Stadt', 'Basel-Stadt', 'Bâle-Ville', 'Basilea Città'],
	FR: ['Freiburg', 'Fribourg', 'Fribourg', 'Friburgo'],
	GE: ['Genf', 'Geneva', 'Genève', 'Ginevra'],
	GL: ['Glarus', 'Glarus', 'Glaris', 'Glarona'],
	GR: ['Graubünden', 'Grisons', 'Grisons', 'Grigioni'],
	JU: ['Jura', 'Jura', 'Jura', 'Giura'],
	LU: ['Luzern', 'Lucerne', 'Lucerne', 'Lucerna'],
	NE: ['Neuenburg', 'Neuchâtel', 'Neuchâtel', 'Neuchâtel'],
	NW: ['Nidwalden', 'Nidwalden', 'Nidwald', 'Nidvaldo'],
	OW: ['Obwalden', 'Obwalden', 'Obwald', 'Obvaldo'],
	SG: ['St. Gallen', 'St. Gallen', 'Saint-Gall', 'San Gallo'],
	SH: ['Schaffhausen', 'Schaffhausen', 'Schaffhouse', 'Sciaffusa'],
	SO: ['Solothurn', 'Solothurn', 'Soleure', 'Soletta'],
	SZ: ['Schwyz', 'Schwyz', 'Schwytz', 'Svitto'],
	TG: ['Thurgau', 'Thurgau', 'Thurgovie', 'Turgovia'],
	TI: ['Tessin', 'Ticino', 'Tessin', 'Ticino'],
	UR: ['Uri', 'Uri', 'Uri', 'Uri'],
	VD: ['Waadt', 'Vaud', 'Vaud', 'Vaud'],
	VS: ['Wallis', 'Valais', 'Valais', 'Vallese'],
	ZG: ['Zug', 'Zug', 'Zoug', 'Zugo'],
	ZH: ['Zürich', 'Zurich', 'Zurich', 'Zurigo']
};

const COLUMN: Record<Locale, number> = { de: 0, en: 1, fr: 2, it: 3 };

/** The canton's name in the locale; the code itself for an unknown one. */
export function cantonName(code: string, locale: Locale): string {
	return NAMES[code]?.[COLUMN[locale]] ?? code;
}

/** Whether the code is a canton's, such as BE. */
export function isCanton(code: string): boolean {
	return code in NAMES;
}
