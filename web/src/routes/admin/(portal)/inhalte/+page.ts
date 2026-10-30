import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const q = url.searchParams.get('q') ?? '';
	if (!q) return { items: [], q };
	const { data, response } = await adminApi(fetch, url.origin).GET('/admin/items', {
		params: { query: { q } }
	});
	if (!data) error(response.status === 403 ? 403 : 500);
	return { items: data.items, q };
};
