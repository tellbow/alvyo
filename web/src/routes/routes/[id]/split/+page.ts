import { redirect } from '@sveltejs/kit';
import { loadRoute } from '#lib/api/routes.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname + url.search)}`);
	return loadRoute(fetch, url, params.id, true);
};
