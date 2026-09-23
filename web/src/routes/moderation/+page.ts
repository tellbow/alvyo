import { error, redirect } from '@sveltejs/kit';
import { api } from '$lib/api/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname)}`);
	const { data, response } = await api(fetch, url.origin).GET('/moderation/reports');
	if (!data) error(response.status === 403 ? 403 : 500);
	return { reports: data.reports };
};
