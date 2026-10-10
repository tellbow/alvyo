import { loadCollection } from '#lib/api/collections.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) =>
	loadCollection(fetch, url, params.id, !!(await parent()).user);
