import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const api = adminApi(fetch, url.origin);
	const [system, jobs] = await Promise.all([api.GET('/admin/system'), api.GET('/admin/jobs')]);
	if (!system.data || !jobs.data) error(system.response.status === 403 ? 403 : 500);
	return { system: system.data, jobs: jobs.data };
};
