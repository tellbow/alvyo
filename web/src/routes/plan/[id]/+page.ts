import { redirect } from '@sveltejs/kit';
import { loadRoute } from '#lib/api/routes.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) => {
	const { route } = await loadRoute(fetch, url, params.id, !!(await parent()).user);
	// Owners and editors edit; everyone else sees the route page.
	if (!route.can_edit) redirect(303, `/routes/${params.id}${url.search}`);
	return { route };
};
