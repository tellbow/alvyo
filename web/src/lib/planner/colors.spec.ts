import { describe, expect, it } from 'vitest';
import { STAGE_COLORS } from '$lib/journeys/colors';
import { SAC_COLOR, contrast, sacInk } from './colors';

// OKLab difference ×100, as seen normally or with deuteranopia/protanopia
// (Machado et al. 2009, full severity): 15 tells neighbours apart with full
// colour vision, 8 with red-green colour blindness.
const CVD = {
	protan: [
		[0.152286, 1.052583, -0.204868],
		[0.114503, 0.786281, 0.099216],
		[-0.003882, -0.048116, 1.051998]
	],
	deutan: [
		[0.367322, 0.860646, -0.227968],
		[0.280085, 0.672501, 0.047413],
		[-0.01182, 0.04294, 0.968881]
	]
};

const linear = (hex: string) =>
	[1, 3, 5].map((i) => {
		const c = parseInt(hex.slice(i, i + 2), 16) / 255;
		return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
	});

function oklab([r, g, b]: number[]) {
	const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	return [
		0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
	];
}

function difference(a: string, b: string, kind?: keyof typeof CVD) {
	const seen = (hex: string) => {
		const c = linear(hex);
		if (!kind) return c;
		return CVD[kind].map((row) =>
			Math.max(0, Math.min(1, row[0] * c[0] + row[1] * c[1] + row[2] * c[2]))
		);
	};
	const [x, y] = [oklab(seen(a)), oklab(seen(b))];
	return 100 * Math.hypot(x[0] - y[0], x[1] - y[1], x[2] - y[2]);
}

describe('colours', () => {
	it('tells neighbouring SAC grades apart', () => {
		const grades = Object.values(SAC_COLOR);
		for (let i = 1; i < grades.length; i++) {
			const [a, b] = [grades[i - 1], grades[i]];
			expect(difference(a, b), `${a} ${b}`).toBeGreaterThanOrEqual(15);
			expect(difference(a, b, 'deutan'), `${a} ${b}`).toBeGreaterThanOrEqual(8);
			expect(difference(a, b, 'protan'), `${a} ${b}`).toBeGreaterThanOrEqual(8);
		}
	});

	it('tells neighbouring stages apart with red-green colour blindness, also when cycling', () => {
		const n = STAGE_COLORS.length;
		for (let i = 0; i < n; i++) {
			const [a, b] = [STAGE_COLORS[i], STAGE_COLORS[(i + 1) % n]];
			expect(difference(a, b, 'deutan'), `${a} ${b}`).toBeGreaterThanOrEqual(8);
			expect(difference(a, b, 'protan'), `${a} ${b}`).toBeGreaterThanOrEqual(8);
		}
	});

	it('writes every grade badge readably', () => {
		for (const grade of [0, 1, 2, 3, 4, 5, 6]) {
			const background = SAC_COLOR[`T${grade}`] ?? '#a8a29e';
			expect(contrast(sacInk(grade), background), `T${grade}`).toBeGreaterThanOrEqual(4.5);
		}
	});
});
