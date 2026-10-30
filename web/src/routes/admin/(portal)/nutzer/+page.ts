import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const q = url.searchParams.get('q') ?? '';
	const page = Math.max(1, Number(url.searchParams.get('page')) || 1);
	const { data, response } = await adminApi(fetch, url.origin).GET('/admin/users', {
		params: { query: { q, page } }
	});
	if (!data) error(response.status === 403 ? 403 : 500);
	return { ...data, q, page, pages: Math.max(1, Math.ceil(data.counts.total / data.page_size)) };
};
