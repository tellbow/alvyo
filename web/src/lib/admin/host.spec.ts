import { describe, expect, it } from 'vitest';
import { adminRedirect } from './host';

describe('adminRedirect', () => {
	const admin = 'https://admin.alvyo.tellbow.ch';
	it('sends /admin on the public host to the admin host', () => {
		expect(adminRedirect(admin, 'alvyo.tellbow.ch', '/admin/meldungen', '?x=1')).toBe(
			'https://admin.alvyo.tellbow.ch/admin/meldungen?x=1'
		);
		expect(adminRedirect(admin, 'alvyo.tellbow.ch', '/admin', '')).toBe(`${admin}/admin`);
	});
	it("leaves other pages, and the admin host's own, alone", () => {
		expect(adminRedirect(admin, 'alvyo.tellbow.ch', '/administrator', '')).toBeUndefined();
		expect(adminRedirect(admin, 'alvyo.tellbow.ch', '/', '')).toBeUndefined();
		expect(adminRedirect(admin, 'admin.alvyo.tellbow.ch', '/admin/meldungen', '')).toBeUndefined();
	});
	it("leads the admin host's root to /admin", () => {
		expect(adminRedirect(admin, 'admin.alvyo.tellbow.ch', '/', '')).toBe('/admin');
	});
	it('does nothing without an admin host', () => {
		expect(adminRedirect('', 'localhost:5173', '/admin', '')).toBeUndefined();
	});
});
