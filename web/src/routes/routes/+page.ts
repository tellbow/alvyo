import { redirect } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname)}`);
	const client = api(fetch, url.origin);
	const [{ data }, { data: shared }] = await Promise.all([
		client.GET('/routes'),
		client.GET('/shared')
	]);
	return { routes: data?.routes ?? [], shared: shared?.routes ?? [] };
};
