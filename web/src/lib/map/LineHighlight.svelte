<script lang="ts">
	import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { ROUTE_PREFIX } from './styles';

	// A part of the route picked in a list (a snow stretch, a protected area
	// crossed): drawn over the line, and the map goes there.
	let {
		map,
		lib,
		parts
	}: {
		map: MapLibreMap;
		lib: typeof MapLibre;
		/** Lines of [lon, lat]; none: nothing shown. */
		parts: number[][][];
	} = $props();

	const ID = ROUTE_PREFIX + 'highlight';

	$effect(() => {
		map.addSource(ID, { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
		map.addLayer({
			id: ID,
			type: 'line',
			source: ID,
			layout: { 'line-cap': 'round', 'line-join': 'round' },
			paint: { 'line-color': '#f28a48', 'line-width': 10, 'line-opacity': 0.75 }
		});
		return () => {
			if (map.getLayer(ID)) map.removeLayer(ID);
			if (map.getSource(ID)) map.removeSource(ID);
		};
	});

	$effect(() => {
		const lines = parts.filter((p) => p.length >= 2);
		(map.getSource(ID) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: lines.map((coordinates) => ({
				type: 'Feature',
				geometry: { type: 'LineString', coordinates },
				properties: {}
			}))
		});
		const all = lines.flat();
		if (all.length === 0) return;
		const bounds = all.reduce(
			(b, c) => b.extend([c[0], c[1]]),
			new lib.LngLatBounds([all[0][0], all[0][1]], [all[0][0], all[0][1]])
		);
		// Above the elevation profile, which is open on a tall map.
		const tall = map.getContainer().clientHeight > 600;
		map.fitBounds(bounds, {
			padding: { top: 60, bottom: tall ? 200 : 60, left: 60, right: 60 },
			maxZoom: 15
		});
	});
</script>
