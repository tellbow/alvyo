import { error } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const { data } = await api(fetch, url.origin).GET('/cantons');
	if (!data) error(503);
	return { cantons: data.cantons };
};
