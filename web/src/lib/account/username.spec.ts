import { describe, expect, it } from 'vitest';
import { badChars } from './username';

describe('badChars', () => {
	it('names each character that is not allowed once', () => {
		expect(badChars('anna-maria.m ü-')).toEqual(['-', '.', ' ', 'ü']);
	});
	it('finds none in a valid name', () => {
		expect(badChars('anna_m2')).toEqual([]);
	});
});
