import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, params }) => {
	const { data } = await api(fetch, url.origin).GET('/live/view/{token}', {
		params: { path: { token: params.token } }
	});
	return { view: data ?? null, token: params.token };
};
