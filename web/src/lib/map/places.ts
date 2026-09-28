import type { FeatureCollection, Point } from 'geojson';
import type { Pin } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';
import { formatHeight } from '$lib/planner/route';
import type { OverlayId, PlaceOverlayId } from './styles';

type Kind = Exclude<Pin['kind'], 'pt_stop'>;
export type PoiKind = 'peak' | 'viewpoint' | 'waterfall' | 'water' | 'shelter';
export const POI_KINDS: PoiKind[] = ['peak', 'viewpoint', 'waterfall', 'water', 'shelter'];

/** What a point of interest is, «Gipfel». */
export function poiLabel(kind: PoiKind): string {
	return {
		peak: m.poi_peak,
		viewpoint: m.poi_viewpoint,
		waterfall: m.poi_waterfall,
		water: m.poi_water,
		shelter: m.poi_shelter
	}[kind]();
}

/** A point of interest's popup: its name (or kind) and kind, a summit's height. */
export function poiText(p: { kind: PoiKind; name: string; ele?: number }): [string, string] {
	const kind = poiLabel(p.kind);
	const detail = p.ele ? `${kind} · ${formatHeight(p.ele)}` : kind;
	return [p.name || kind, p.name ? detail : p.ele ? formatHeight(p.ele) : ''];
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

/** The kinds to fetch for the chosen overlays at this zoom. */
export function placeKinds(overlays: OverlayId[], zoom: number): Kind[] {
	return Object.entries(PLACE_OVERLAYS)
		.filter(([id, o]) => overlays.includes(id as PlaceOverlayId) && zoom >= o.minZoom)
		.flatMap(([, o]) => o.kinds);
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
