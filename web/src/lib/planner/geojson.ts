import type { FeatureCollection, LineString } from 'geojson';
import type { Anchor, LegSlot } from './planner.svelte';

export type LegProps = { leg: number; state: LegSlot['state']; straight: boolean };

/** One line per leg: the computed path, or a placeholder between anchors. */
export function legFeatures(
	anchors: Anchor[],
	legs: LegSlot[]
): FeatureCollection<LineString, LegProps> {
	return {
		type: 'FeatureCollection',
		features: legs.map((slot, i) => {
			const from = anchors[i];
			const to = anchors[i + 1];
			const coordinates =
				slot.state === 'ok'
					? slot.leg.coordinates.map((c) => [c[0], c[1]])
					: [
							[from.lon, from.lat],
							[to.lon, to.lat]
						];
			return {
				type: 'Feature',
				properties: { leg: i, state: slot.state, straight: to.straight },
				geometry: { type: 'LineString', coordinates }
			};
		})
	};
}
