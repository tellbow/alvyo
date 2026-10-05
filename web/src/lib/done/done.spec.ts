import { describe, expect, it } from 'vitest';
import { doneDate, passes, readDone } from './done';

describe('done', () => {
	it('formats a day without shifting it', () => {
		expect(doneDate('2026-08-01', 'de-CH')).toBe('1.8.2026');
	});

	it('reads the filter and lets the right items pass', () => {
		expect(readDone(new URLSearchParams('done=planned'))).toBe('planned');
		expect(readDone(new URLSearchParams('done=x'))).toBe('');
		expect(passes('done', '2026-08-01')).toBe(true);
		expect(passes('done', undefined)).toBe(false);
		expect(passes('planned', undefined)).toBe(true);
		expect(passes('', '2026-08-01')).toBe(true);
	});
});
