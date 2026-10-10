import { redirect } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname + url.search)}`);
	const client = api(fetch, url.origin);
	const [{ data: lists }, { data: link }] = await Promise.all([
		client.GET('/me/friends'),
		client.GET('/me/friend-link')
	]);
	return {
		lists: lists ?? { friends: [], incoming: [], outgoing: [] },
		token: link?.token ?? ''
	};
};
