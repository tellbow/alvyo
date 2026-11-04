import { redirect } from '@sveltejs/kit';
import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) redirect(303, `/login?redirect=${encodeURIComponent(url.pathname + url.search)}`);
	const year = Number(url.searchParams.get('year'));
	const valid = Number.isInteger(year) && year > 0 && year < 10000;
	const { data } = await api(fetch, url.origin).GET('/me/hiked', {
		params: { query: valid ? { year } : {} }
	});
	return { year: valid ? year : undefined, hiked: data };
};
