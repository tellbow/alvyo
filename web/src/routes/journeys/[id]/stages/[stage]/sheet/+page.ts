import { error } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import { loadJourney } from '#lib/api/journeys.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) => {
	const { journey, token } = await loadJourney(fetch, url, params.id, !!(await parent()).user);
	const index = journey.stage_list.findIndex((s) => s.id === params.stage);
	const routeId = journey.stage_list[index]?.route?.id;
	if (!routeId) error(404);
	const { data: route } = await api(fetch, url.origin).GET('/routes/{id}', {
		params: { path: { id: routeId }, query: token ? { t: token } : {} }
	});
	if (!route) error(500);
	return { journey, token, index, route };
};
