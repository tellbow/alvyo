import { describe, expect, it } from 'vitest';
import { m } from '#lib/paraglide/messages.js';

describe('counts', () => {
	it('say one in the singular', () => {
		expect(m.community_comments({ n: 1 }, { locale: 'de' })).toBe('1 Kommentar');
		expect(m.community_comments({ n: 3 }, { locale: 'de' })).toBe('3 Kommentare');
		expect(m.community_likes({ n: 1 }, { locale: 'en' })).toBe('liked once');
		expect(m.collection_stages({ n: 1 }, { locale: 'it' })).toBe('1 tappa');
		expect(m.collection_stages({ n: 0 }, { locale: 'fr' })).toBe('0 étape');
	});
});
