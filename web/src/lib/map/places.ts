import type { FeatureCollection, Point } from 'geojson';
import type { Pin } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';
import { formatHeight } from '$lib/planner/route';
import type { OverlayId, PlaceOverlayId } from './styles';

type Kind = Exclude<Pin['kind'], 'pt_stop'>;
export type PoiKind =
	| 'peak'
	| 'viewpoint'
	| 'waterfall'
	| 'water'
	| 'shelter'
	| 'firepit'
	| 'picnic'
	| 'restaurant'
	| 'toilets'
	| 'cablecar';
export const POI_KINDS: PoiKind[] = [
	'peak',
	'viewpoint',
	'waterfall',
	'water',
	'shelter',
	'firepit',
	'picnic',
	'restaurant',
	'toilets',
	'cablecar'
];

/** What a point of interest is, «Gipfel». */
export function poiLabel(kind: PoiKind): string {
	return {
		peak: m.poi_peak,
		viewpoint: m.poi_viewpoint,
		waterfall: m.poi_waterfall,
		water: m.poi_water,
		shelter: m.poi_shelter,
		firepit: m.poi_firepit,
		picnic: m.poi_picnic,
		restaurant: m.poi_restaurant,
		toilets: m.poi_toilets,
		cablecar: m.poi_cablecar
	}[kind]();
}

/** A point of interest's popup: its name (or kind) and kind, a summit's height. */
export function poiText(p: { kind: PoiKind; name: string; ele?: number }): [string, string] {
	const kind = poiLabel(p.kind);
	const detail = p.ele ? `${kind} · ${formatHeight(p.ele)}` : kind;
	return [p.name || kind, p.name ? detail : p.ele ? formatHeight(p.ele) : ''];
}

/** A point along a route, as `GET /routes/{id}/pois` gives it. */
export type Poi = { kind: PoiKind; name: string; ele?: number; at: number[]; along_m: number };

/** Kinds that come many at once in a town (fountains, restaurants): listed together. */
const GROUPED: PoiKind[] = ['water', 'toilets', 'restaurant', 'picnic', 'firepit', 'shelter'];

/** A line of the list along a route: one point, or `count` of its kind up to `to_m`. */
export type PoiRow = Poi & { count: number; to_m: number };

/**
 * The points along a route as lines to list: those of a kind that comes many
 * at once within `withinM` of the first of them become one line; summits,
 * viewpoints, waterfalls and cable cars stay one each.
 */
export function groupPois(pois: Poi[], withinM = 1000): PoiRow[] {
	const rows: PoiRow[] = [];
	const open = new Map<PoiKind, PoiRow>();
	for (const p of pois) {
		const grouped = GROUPED.includes(p.kind);
		const row = open.get(p.kind);
		if (grouped && row && p.along_m - row.along_m <= withinM) {
			row.count++;
			row.to_m = p.along_m;
			continue;
		}
		const next = { ...p, count: 1, to_m: p.along_m };
		rows.push(next);
		if (grouped) open.set(p.kind, next);
	}
	return rows;
}

export function isPoi(kind: string): kind is PoiKind {
	return (POI_KINDS as string[]).includes(kind);
}

/** What each place overlay shows, and from which zoom: below, too many points. */
export const PLACE_OVERLAYS: Record<PlaceOverlayId, { kinds: Kind[]; minZoom: number }> = {
	huts: { kinds: ['hut'], minZoom: 8 },
	lodging: { kinds: ['hotel', 'campsite'], minZoom: 10 },
	pois: { kinds: POI_KINDS, minZoom: 12 }
};

/** The kinds to fetch for the chosen overlays at this zoom, along the way only those chosen. */
export function placeKinds(
	overlays: OverlayId[],
	zoom: number,
	poiKinds: PoiKind[] = POI_KINDS
): Kind[] {
	return Object.entries(PLACE_OVERLAYS)
		.filter(([id, o]) => overlays.includes(id as PlaceOverlayId) && zoom >= o.minZoom)
		.flatMap(([, o]) => o.kinds)
		.filter((k) => !isPoi(k) || poiKinds.includes(k));
}

export function placeFeatures(pins: Pin[]): FeatureCollection<Point> {
	return {
		type: 'FeatureCollection',
		features: pins.map((p) => ({
			type: 'Feature',
			geometry: { type: 'Point', coordinates: [p.lon, p.lat] },
			properties: {
				id: p.id,
				kind: p.kind,
				name: p.name,
				detail: p.detail,
				website: p.website ?? ''
			}
		}))
	};
}

/** The website as a link target: only http(s), OSM holds free text. */
export function webLink(url: string | undefined): string | undefined {
	try {
		const u = new URL(url ?? '');
		return u.protocol === 'http:' || u.protocol === 'https:' ? u.href : undefined;
	} catch {
		return undefined;
	}
}
