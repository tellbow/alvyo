import { error, redirect } from '@sveltejs/kit';
import { api } from './client';

/**
 * Loads a route for a page; `?t=` carries the share token of unlisted routes.
 * Anonymous visitors of a private route (e.g. from an invitation e-mail) are
 * sent to log in first.
 */
export async function loadRoute(fetchFn: typeof fetch, url: URL, id: string, loggedIn: boolean) {
	const t = url.searchParams.get('t') ?? undefined;
	const { data, response } = await api(fetchFn, url.origin).GET('/routes/{id}', {
		params: { path: { id }, query: t ? { t } : {} }
	});
	if (response.status === 404 && !loggedIn && !t) {
		redirect(303, `/login?redirect=${encodeURIComponent(url.pathname)}`);
	}
	if (!data) error(response.status === 404 ? 404 : 500);
	return { route: data, token: t };
}
