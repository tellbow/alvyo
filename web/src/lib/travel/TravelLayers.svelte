<script lang="ts">
	import type { GeoJSONSource, Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import type { FeatureCollection, LineString } from 'geojson';
	import type { Trip } from '#lib/api/client.js';
	import { ROUTE_PREFIX } from '#lib/map/styles.js';
	import { tripLines } from './travel';

	/** The chosen trips from and to home: rides dashed, walks dotted. */
	let { map, lib, trips }: { map: MapLibreMap; lib: typeof MapLibre; trips: Trip[] } = $props();

	const SRC = `${ROUTE_PREFIX}travel`;
	const empty = { type: 'FeatureCollection' as const, features: [] };

	function addLayers() {
		if (map.getSource(SRC)) return;
		map.addSource(SRC, { type: 'geojson', data: empty });
		map.addLayer({
			id: `${ROUTE_PREFIX}travel-casing`,
			type: 'line',
			source: SRC,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': '#ffffff', 'line-width': 6, 'line-opacity': 0.8 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}travel-ride`,
			type: 'line',
			source: SRC,
			filter: ['==', ['get', 'kind'], 'ride'],
			paint: { 'line-color': '#1d4ed8', 'line-width': 3.5, 'line-dasharray': [2, 1.5] }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}travel-walk`,
			type: 'line',
			source: SRC,
			filter: ['==', ['get', 'kind'], 'walk'],
			layout: { 'line-cap': 'round' },
			paint: { 'line-color': '#1d4ed8', 'line-width': 3, 'line-dasharray': [0.1, 2] }
		});
	}

	function render() {
		const all: FeatureCollection<LineString> = {
			type: 'FeatureCollection',
			features: trips.flatMap((t) => tripLines(t).features)
		};
		(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(all);
		// Zoom out to the whole way, home included, when it reaches beyond the view.
		const view = map.getBounds();
		const points = all.features.flatMap((f) => f.geometry.coordinates);
		if (points.every((p) => view.contains(p as [number, number]))) return;
		const wider = points.reduce(
			(b, p) => b.extend(p as [number, number]),
			new lib.LngLatBounds(view.getSouthWest(), view.getNorthEast())
		);
		map.fitBounds(wider, { padding: 40, duration: 400 });
	}

	$effect(() => {
		addLayers();
		const onStyle = () => {
			addLayers();
			render();
		};
		map.on('style.load', onStyle);
		return () => map.off('style.load', onStyle);
	});

	$effect(() => {
		void trips;
		render();
	});
</script>
