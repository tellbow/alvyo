import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { contrast } from '$lib/planner/colors';

// The colours of layout.css, light and chosen dark.
const css = readFileSync(new URL('../../routes/layout.css', import.meta.url), 'utf8');
function palette(selector: string): Record<string, string> {
	const block = css.slice(css.indexOf(selector)).split('}')[0];
	return Object.fromEntries(
		[...block.matchAll(/--alvyo-([\w-]+):\s*(#[0-9a-f]{6})/g)].map((m) => [m[1], m[2]])
	);
}

describe('palette', () => {
	for (const [theme, colours] of [
		['light', palette(':root {')],
		['dark', palette(":root[data-theme='dark'] {")]
	] as const) {
		it(`text colours read on every ground (${theme})`, () => {
			const grounds = ['ground', 'surface', 'stone-50', 'stone-100'];
			for (const text of ['stone-500', 'stone-600', 'stone-700', 'stone-800', 'stone-900']) {
				for (const ground of grounds) {
					const ratio = contrast(colours[text], colours[ground]);
					expect(ratio, `${text} on ${ground}`).toBeGreaterThanOrEqual(4.5);
				}
			}
			for (const ground of ['ground', 'surface']) {
				expect(contrast(colours['accent-ink'], colours[ground])).toBeGreaterThanOrEqual(4.5);
			}
		});
	}

	it('uses no stone-400 for text: it reads on no ground', () => {
		const pages = import.meta.glob<string>('/src/**/*.svelte', {
			query: '?raw',
			import: 'default',
			eager: true
		});
		const offenders = Object.entries(pages)
			.filter(([, src]) => /\btext-stone-400\b/.test(src))
			.map(([path]) => path);
		expect(offenders).toEqual([]);
	});
});
