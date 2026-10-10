import { error } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url }) => {
	const { data, response } = await api(fetch, url.origin).GET('/users/{username}', {
		params: { path: { username: params.username } }
	});
	if (!data) error(response.status === 404 ? 404 : 500);
	return { profile: data };
};
