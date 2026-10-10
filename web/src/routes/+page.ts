import { api } from '#lib/api/client.js';
import type { PageLoad } from './$types';

// All of Switzerland: the public hikes nearest its centre.
const SWITZERLAND = '5.9,45.8,10.5,47.9';

export const load: PageLoad = async ({ fetch, url }) => {
	const { data } = await api(fetch, url.origin).GET('/discover', {
		params: { query: { bbox: SWITZERLAND } }
	});
	return { hikes: data?.items.slice(0, 4) ?? [] };
};
