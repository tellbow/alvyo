import { api } from '#lib/api/client.js';
import type { LayoutLoad } from './$types';

// In the layout, as it stays the same for every year.
export const load: LayoutLoad = async ({ fetch, url, parent }) => {
	const { user } = await parent();
	if (!user) return { achievements: undefined };
	const { data } = await api(fetch, url.origin).GET('/me/achievements');
	return { achievements: data };
};
