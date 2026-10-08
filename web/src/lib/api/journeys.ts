import { error, redirect } from '@sveltejs/kit';
import { api } from './client';

/**
 * Loads a journey for a page; `?t=` carries the share token of unlisted journeys.
 * Anonymous visitors of a private journey (e.g. from an invitation e-mail) are
 * sent to log in first.
 */
export async function loadJourney(fetchFn: typeof fetch, url: URL, id: string, loggedIn: boolean) {
	const t = url.searchParams.get('t') ?? undefined;
	const { data, response } = await api(fetchFn, url.origin).GET('/journeys/{id}', {
		params: { path: { id }, query: t ? { t } : {} }
	});
	if (response.status === 404 && !loggedIn && !t) {
		redirect(303, `/login?redirect=${encodeURIComponent(url.pathname + url.search)}`);
	}
	if (!data) error(response.status === 404 ? 404 : 500);
	return { journey: data, token: t };
}
