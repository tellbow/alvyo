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
