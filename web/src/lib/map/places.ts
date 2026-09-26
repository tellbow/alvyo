import type { FeatureCollection, Point } from 'geojson';
import type { Pin } from '$lib/api/client';
import type { OverlayId, PlaceOverlayId } from './styles';

type Kind = 'hut' | 'hotel' | 'campsite';

/** What each place overlay shows, and from which zoom: below, too many points. */
export const PLACE_OVERLAYS: Record<PlaceOverlayId, { kinds: Kind[]; minZoom: number }> = {
	huts: { kinds: ['hut'], minZoom: 8 },
	lodging: { kinds: ['hotel', 'campsite'], minZoom: 10 }
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
