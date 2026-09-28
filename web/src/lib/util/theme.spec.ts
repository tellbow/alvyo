import { describe, expect, it } from 'vitest';
import { parseTheme, themeAttribute } from './theme';

describe('theme', () => {
	it('follows the system unless light or dark was chosen', () => {
		expect(parseTheme('light')).toBe('light');
		expect(parseTheme('dark')).toBe('dark');
		expect(parseTheme(undefined)).toBe('system');
		expect(parseTheme('')).toBe('system');
		expect(parseTheme('sepia')).toBe('system');
	});

	it('leaves the attribute empty for the system setting', () => {
		expect(themeAttribute('system')).toBe('');
		expect(themeAttribute('dark')).toBe('dark');
	});
});
