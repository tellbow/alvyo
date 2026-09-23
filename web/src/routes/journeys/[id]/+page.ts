import { loadJourney } from '$lib/api/journeys';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url, parent }) =>
	loadJourney(fetch, url, params.id, !!(await parent()).user);
