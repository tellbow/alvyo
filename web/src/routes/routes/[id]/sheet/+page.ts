import { loadRoute } from '#lib/api/routes.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) =>
	loadRoute(fetch, url, params.id, !!(await parent()).user);
