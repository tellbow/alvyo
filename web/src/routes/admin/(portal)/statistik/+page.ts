import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const { data, response } = await adminApi(fetch, url.origin).GET('/admin/stats');
	if (!data) error(response.status === 403 ? 403 : 500);
	return { stats: data };
};
