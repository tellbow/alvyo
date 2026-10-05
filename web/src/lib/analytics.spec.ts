import { describe, expect, it } from 'vitest';
import { analyticsUrl } from './analytics';

describe('analyticsUrl', () => {
	const at = (s: string) => analyticsUrl(new URL(s, 'https://alvyo.tellbow.ch'));

	it('leaves out what gives access', () => {
		expect(at('/routes/abc?t=secret#x')).toBe('https://alvyo.tellbow.ch/routes/abc');
		expect(at('/reset-password?token=secret')).toBe('https://alvyo.tellbow.ch/reset-password');
		expect(at('/live/secret')).toBe('https://alvyo.tellbow.ch/live/-');
		expect(at('/en/friends/invite/secret')).toBe('https://alvyo.tellbow.ch/en/friends/invite/-');
	});

	it('keeps ordinary pages', () => {
		expect(at('/fr/discover')).toBe('https://alvyo.tellbow.ch/fr/discover');
		expect(at('/u/anna')).toBe('https://alvyo.tellbow.ch/u/anna');
	});
});
