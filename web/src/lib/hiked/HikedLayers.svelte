<script lang="ts">
	import type { GeoJSON } from 'geojson';
	import type { GeoJSONSource, MapLayerMouseEvent, Map as MapLibreMap } from 'maplibre-gl';
	import type { HikedItem } from '#lib/api/client.js';
	import { OSM_ATTRIBUTION, ROUTE_PREFIX } from '#lib/map/styles.js';
	import { ROUTE_COLOR } from '#lib/planner/colors.js';

	let {
		map,
		items,
		onclick
	}: { map: MapLibreMap; items: HikedItem[]; onclick: (it: HikedItem) => void } = $props();

	const SRC = `${ROUTE_PREFIX}hiked`;
	const LINE = `${ROUTE_PREFIX}hiked-line`;

	const features = (): GeoJSON => ({
		type: 'FeatureCollection',
		features: items.map((it, i) => ({
			type: 'Feature',
			properties: { i },
			geometry: { type: 'MultiLineString', coordinates: it.lines }
		}))
	});

	function addLayers() {
		if (map.getSource(SRC)) return;
		map.addSource(SRC, { type: 'geojson', data: features(), attribution: OSM_ATTRIBUTION });
		// See-through without a casing: paths walked more often get darker.
		map.addLayer({
			id: LINE,
			type: 'line',
			source: SRC,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': ROUTE_COLOR, 'line-width': 4, 'line-opacity': 0.6 }
		});
	}

	$effect(() => {
		addLayers();
		const onStyle = () => addLayers();
		map.on('style.load', onStyle);
		return () => map.off('style.load', onStyle);
	});

	$effect(() => {
		void items;
		(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(features());
	});

	$effect(() => {
		const click = (e: MapLayerMouseEvent) => {
			const it = items[Number(e.features?.[0]?.properties?.i)];
			if (it) onclick(it);
		};
		const enter = () => (map.getCanvas().style.cursor = 'pointer');
		const leave = () => (map.getCanvas().style.cursor = '');
		map.on('click', LINE, click);
		map.on('mouseenter', LINE, enter);
		map.on('mouseleave', LINE, leave);
		return () => {
			map.off('click', LINE, click);
			map.off('mouseenter', LINE, enter);
			map.off('mouseleave', LINE, leave);
		};
	});
</script>
