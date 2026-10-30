import type { Handle } from '@sveltejs/kit/hooks';

/**
 * Where a request belongs when the admin portal has a host of its own
 * (adminURL): /admin on another host goes there, the admin host's root to
 * /admin; undefined when it stays. host is the request's Host header.
 */
export function adminRedirect(
	adminURL: string,
	host: string,
	path: string,
	search: string
): string | undefined {
	if (!adminURL) return undefined;
	const admin = new URL(adminURL);
	const onAdmin = host === admin.host;
	if (!onAdmin && (path === '/admin' || path.startsWith('/admin/'))) {
		return admin.origin + path + search;
	}
	if (onAdmin && path === '/') return '/admin';
	return undefined;
}

/** The hook: answers a redirect itself, as SvelteKit's redirect() refuses
 * other hosts (redirect_external_not_allowed). The Host header decides:
 * with ORIGIN set (the cluster), event.url always has the public host. */
export const adminHost =
	(adminURL: string): Handle =>
	({ event, resolve }) => {
		const to = adminRedirect(
			adminURL,
			event.request.headers.get('host') ?? event.url.host,
			event.url.pathname,
			event.url.search
		);
		if (to) return new Response(null, { status: 307, headers: { location: to } });
		return resolve(event);
	};
