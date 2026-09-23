import { redirect } from '@sveltejs/kit';
import { api } from '$lib/api/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname)}`);
	const { data } = await api(fetch, url.origin).GET('/feed');
	return { items: data?.items ?? [], next: data?.next };
};
