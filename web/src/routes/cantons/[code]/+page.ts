import { error } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import { isCanton } from '#lib/cantons.js';
import type { PageLoad } from './$types';

/** A canton's page is /cantons/be: one address for each, in lower case. */
export const load: PageLoad = async ({ fetch, params, url }) => {
	const code = params.code.toUpperCase();
	if (params.code !== code.toLowerCase() || !isCanton(code)) error(404);
	const { data, response } = await api(fetch, url.origin).GET('/cantons/{code}', {
		params: { path: { code } }
	});
	if (!data) error(response.status === 404 ? 404 : 503);
	return { code, items: data.items };
};
