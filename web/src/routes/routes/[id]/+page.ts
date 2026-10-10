import { loadRevision, loadRoute } from '#lib/api/routes.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) => {
	const version = Number(url.searchParams.get('version'));
	if (version > 0) return loadRevision(fetch, url, params.id, version);
	return loadRoute(fetch, url, params.id, !!(await parent()).user);
};
