import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// Universal links: iOS opens these addresses in the app (team id and
// bundle id) instead of Safari, as Android does with assetlinks.json and
// the same paths (AndroidManifest.xml): a route, journey or collection by
// its id (not /routes/map or /journeys/plan), and invites; also in English,
// French and Italian.
const kinds = [
	'/routes/????????-*',
	'/journeys/????????-*',
	'/collections/????????-*',
	'/friends/invite/*'
];

export const GET: RequestHandler = () =>
	json(
		{
			applinks: {
				details: [
					{
						appIDs: ['HYFKN2HQXF.ch.tellbow.alvyo'],
						components: ['', '/en', '/fr', '/it'].flatMap((prefix) =>
							kinds.map((path) => ({ '/': prefix + path }))
						)
					}
				]
			}
		},
		{ headers: { 'cache-control': 'public, max-age=3600' } }
	);
