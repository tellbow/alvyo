import { describe, expect, it } from 'vitest';
import { addTag, hasTag, MAX_TAGS } from './tags';

describe('tags', () => {
	it('adds typed tags once, ignoring case', () => {
		expect(addTag([], '  mit   Kindern ')).toEqual(['mit Kindern']);
		expect(addTag(['Winter'], 'winter')).toEqual(['Winter']);
		expect(addTag(['Winter'], ' ')).toEqual(['Winter']);
		const full = Array.from({ length: MAX_TAGS }, (_, i) => `t${i}`);
		expect(addTag(full, 'one more')).toBe(full);
	});

	it('filters without case', () => {
		expect(hasTag(['Winter', 'Tessin'], 'tessin')).toBe(true);
		expect(hasTag(['Winter'], 'Tessin')).toBe(false);
		expect(hasTag([], null)).toBe(true);
	});
});
