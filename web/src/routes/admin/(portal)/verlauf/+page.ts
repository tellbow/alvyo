import { error } from '@sveltejs/kit';
import { adminApi } from '#lib/api/client.js';
import type { PageLoad } from './$types';

const areas = ['meldungen', 'nutzer', 'inhalte'] as const;

export const load: PageLoad = async ({ fetch, url }) => {
	const a = url.searchParams.get('area');
	const area = areas.find((x) => x === a);
	const { data, response } = await adminApi(fetch, url.origin).GET('/admin/log', {
		params: { query: area ? { area } : {} }
	});
	if (!data) error(response.status === 403 ? 403 : 500);
	return { entries: data.entries, area };
};
