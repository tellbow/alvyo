import { describe, expect, it } from 'vitest';
import de from '../../../messages/de.json';
import en from '../../../messages/en.json';
import fr from '../../../messages/fr.json';
import it_ from '../../../messages/it.json';

const lines = (msgs: Record<string, unknown>, key: string) => String(msgs[key]).split('\n').length;

describe('news', () => {
	// Each language lists the same changes, so the bullets line up.
	it('has as many lines in every language', () => {
		for (const key of Object.keys(de).filter((k) => k.startsWith('news_'))) {
			const n = lines(de, key);
			for (const other of [en, fr, it_]) expect([key, lines(other, key)]).toEqual([key, n]);
		}
	});
});
