import { readdirSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('messages', () => {
	// A key twice in a file: the last wins silently and the first text is lost.
	it('have no key twice in a file', () => {
		for (const f of readdirSync('messages').filter((f) => f.endsWith('.json'))) {
			const keys = [...readFileSync(`messages/${f}`, 'utf8').matchAll(/^\t"([^"]+)":/gm)].map(
				(m) => m[1]
			);
			expect(
				keys.filter((k, i) => keys.indexOf(k) !== i),
				f
			).toEqual([]);
		}
	});
});
