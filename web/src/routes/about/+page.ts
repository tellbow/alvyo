import { api } from '$lib/api/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url }) => {
	const { data } = await api(fetch, url.origin).GET('/version');
	return { version: data };
};
