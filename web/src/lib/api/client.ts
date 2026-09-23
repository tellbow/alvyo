import createClient from 'openapi-fetch';
import type { components, paths } from './schema';

export type Me = components['schemas']['Me'];
export type Leg = components['schemas']['Leg'];
export type ApiError = components['schemas']['ErrorModel'];
export type Route = components['schemas']['RouteBody'];
export type RouteSummary = components['schemas']['RouteSummary'];
export type JourneySummary = components['schemas']['JourneySummary'];
export type Place = components['schemas']['Place'];

/** Huma cannot mark nested objects as nullable; the API sends null for these. */
type Nullable<T, K extends keyof T> = Omit<T, K> & { [P in K]: T[P] | null };
export type JourneyStage = Nullable<
	components['schemas']['JourneyStage'],
	'route' | 'gap' | 'start_place' | 'end_place'
>;
export type Journey = Omit<components['schemas']['JourneyBody'], 'stage_list'> & {
	stage_list: JourneyStage[];
};
export type StagePatch = components['schemas']['UpdateStageInputBody'];
export type Grant = components['schemas']['Grant'];
export type SharedRoute = components['schemas']['RouteShared'];
export type SharedJourney = components['schemas']['JourneyShared'];
export type Collection = components['schemas']['CollectionBody'];
export type CollectionSummary = components['schemas']['CollectionSummary'];
export type CollectionItem = components['schemas']['CollectionItem'];
export type SharedCollection = components['schemas']['CollectionShared'];
export type DiscoverItem = components['schemas']['DiscoverItem'];
export type Profile = components['schemas']['ProfileOutputBody'];

/**
 * Typed client for the odysgeh API. Pass SvelteKit's `fetch` in load
 * functions. On the server the base URL must be absolute (`url.origin`);
 * hooks.server.ts rewrites it to the internal API address.
 */
export function api(fetchFn: typeof fetch = fetch, origin = '') {
	return createClient<paths>({ baseUrl: `${origin}/api/v1`, fetch: fetchFn });
}

/** Locations of field errors in an API error, e.g. "body.email". */
export function errorLocations(err: ApiError | undefined): string[] {
	return (err?.errors ?? []).map((e) => e.location ?? '');
}
