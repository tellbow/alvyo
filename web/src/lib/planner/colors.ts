/** SAC grades in the colours of the Swiss trail markings (yellow, red, blue). */
export const SAC_COLOR: Record<string, string> = {
	T1: '#eab308',
	T2: '#dc2626',
	T3: '#991b1b',
	T4: '#2563eb',
	T5: '#1d4ed8',
	T6: '#1e3a8a'
};

export const TRAIL_COLOR: Record<string, string> = {
	Wanderweg: '#eab308',
	Bergwanderweg: '#dc2626',
	Alpinwanderweg: '#2563eb',
	none: '#a8a29e'
};

export const SURFACE_COLOR: Record<string, string> = {
	paved: '#57534e',
	gravel: '#a8a29e',
	natural: '#65a30d',
	unknown: '#e7e5e4'
};

export const WAY_COLOR: Record<string, string> = {
	road: '#57534e',
	track: '#a16207',
	path: '#65a30d',
	steps: '#7c3aed',
	unknown: '#e7e5e4'
};
