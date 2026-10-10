import { error, redirect } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import { loadJourney } from '#lib/api/journeys.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) => {
	const { journey } = await loadJourney(fetch, url, params.id, !!(await parent()).user);
	if (!journey.can_edit) redirect(303, `/journeys/${params.id}${url.search}`);
	const index = journey.stage_list.findIndex((s) => s.id === params.stage);
	if (index < 0) error(404);
	const routeId = journey.stage_list[index].route?.id;
	let route;
	if (routeId) {
		const res = await api(fetch, url.origin).GET('/routes/{id}', {
			params: { path: { id: routeId } }
		});
		route = res.data;
	}
	return { journey, index, route };
};
