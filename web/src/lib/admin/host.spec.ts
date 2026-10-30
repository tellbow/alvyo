import { describe, expect, it } from 'vitest';
import type { RequestEvent } from '@sveltejs/kit';
import { adminHost, adminRedirect } from './host';

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

describe('adminHost', () => {
	// The cluster: ORIGIN gives every request the public host in event.url.
	const event = (host: string, path: string) =>
		({
			url: new URL(`https://alvyo.tellbow.ch${path}`),
			request: new Request(`https://alvyo.tellbow.ch${path}`, { headers: { host } })
		}) as unknown as RequestEvent;
	const resolve = async () => new Response('page');
	const handle = adminHost('https://admin.alvyo.tellbow.ch');

	it('redirects to the other host itself, which redirect() refuses', async () => {
		const res = await handle({ event: event('alvyo.tellbow.ch', '/admin'), resolve });
		expect(res.status).toBe(307);
		expect(res.headers.get('location')).toBe('https://admin.alvyo.tellbow.ch/admin');
	});
	it('serves the admin host by its Host header', async () => {
		const res = await handle({ event: event('admin.alvyo.tellbow.ch', '/admin'), resolve });
		expect(await res.text()).toBe('page');
	});
});
