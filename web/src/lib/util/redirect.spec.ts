import { describe, expect, it } from 'vitest';
import { safeRedirect } from './redirect';

describe('safeRedirect', () => {
	it('keeps local paths', () => {
		expect(safeRedirect('/plan?x=1')).toBe('/plan?x=1');
	});
	it('rejects other sites and empty values', () => {
		expect(safeRedirect('https://evil.example')).toBe('/');
		expect(safeRedirect('//evil.example')).toBe('/');
		expect(safeRedirect(null)).toBe('/');
	});
});
