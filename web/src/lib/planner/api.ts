import { api, type Leg } from '#lib/api/client.js';
import { LegError, type LegRequest } from './planner.svelte';

/** Computes a leg with the API; throws LegError with the HTTP status. */
export async function fetchLeg(req: LegRequest): Promise<Leg> {
	const { data, response } = await api().POST('/routing/leg', {
		body: {
			from: req.from,
			to: req.to,
			profile: req.profile,
			straight: req.straight,
			...(req.through ? { through: req.through } : {})
		}
	});
	if (!data) throw new LegError(response.status);
	return data;
}
