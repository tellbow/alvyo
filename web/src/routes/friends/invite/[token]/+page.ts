import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, params, url }) => {
	const { data } = await api(fetch, url.origin).GET('/friend-invites/{token}', {
		params: { path: { token: params.token } }
	});
	return { inviter: data ?? null };
};
