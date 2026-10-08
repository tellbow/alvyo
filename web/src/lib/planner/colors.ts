/**
 * SAC grades in the colours of the Swiss trail markings (yellow, red, blue),
 * the steps of a colour far enough apart to tell neighbours apart
 * (colors.spec.ts).
 */
export const SAC_COLOR: Record<string, string> = {
	T1: '#eab308',
	T2: '#dc2626',
	T3: '#7f1d1d',
	T4: '#60a5fa',
	T5: '#2563eb',
	T6: '#1e3a8a'
};

/** The line of the route being planned or shown (also var(--alvyo-route) in CSS). */
export const ROUTE_COLOR = '#a21caf';

/** A route without a grade. */
const SAC_NONE = '#8a978f';

/** The badge of a grade (0: none). */
export const sacBackground = (grade: number) => SAC_COLOR[`T${grade}`] ?? SAC_NONE;

/** Text on a grade's badge: white where it reads (4.5:1), else near-black. */
export const sacInk = (grade: number) =>
	contrast('#ffffff', sacBackground(grade)) >= 4.5 ? '#ffffff' : '#1a0f08';

const linear = (hex: string) =>
	[1, 3, 5].map((i) => {
		const c = parseInt(hex.slice(i, i + 2), 16) / 255;
		return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
	});

/** WCAG contrast ratio of two #rrggbb colours. */
export function contrast(a: string, b: string): number {
	const lum = (h: string) => {
		const [r, g, bl] = linear(h);
		return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
	};
	const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
}

export const TRAIL_COLOR: Record<string, string> = {
	Wanderweg: '#eab308',
	Bergwanderweg: '#dc2626',
	Alpinwanderweg: '#2563eb',
	none: '#8a978f'
};

export const SURFACE_COLOR: Record<string, string> = {
	paved: '#56645c',
	gravel: '#8a978f',
	natural: '#65a30d',
	unknown: '#dce3dc'
};

export const WAY_COLOR: Record<string, string> = {
	road: '#56645c',
	track: '#a16207',
	path: '#65a30d',
	steps: '#7c3aed',
	unknown: '#dce3dc'
};
