<script lang="ts">
	import type { GeoJSONSource, MapLayerMouseEvent, Map as MapLibreMap } from 'maplibre-gl';
	import type { FeatureCollection, MultiLineString } from 'geojson';
	import type { CollectionItem } from '$lib/api/client';
	import { stageColor } from '$lib/journeys/colors';
	import { ROUTE_PREFIX } from '$lib/map/styles';

	let {
		map,
		items,
		highlight,
		onclick,
		color = stageColor
	}: {
		map: MapLibreMap;
		/** Collection items, or anything else with an id and lines (discovery). */
		items: Pick<CollectionItem, 'id' | 'lines'>[];
		highlight?: string;
		/** Called with the id of a clicked line. */
		onclick?: (id: string) => void;
		/** Colour of the i-th item's line; by default cycled like stages. */
		color?: (i: number) => string;
	} = $props();

	const SRC = `${ROUTE_PREFIX}collection`;

	function features(): FeatureCollection<MultiLineString> {
		return {
			type: 'FeatureCollection',
			features: items.map((it, i) => ({
				type: 'Feature',
				properties: { id: it.id, color: color(i), highlight: it.id === highlight },
				geometry: { type: 'MultiLineString', coordinates: it.lines }
			}))
		};
	}

	function addLayers() {
		if (map.getSource(SRC)) return;
		map.addSource(SRC, {
			type: 'geojson',
			data: { type: 'FeatureCollection', features: [] },
			attribution: '© OpenStreetMap contributors'
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}collection-casing`,
			type: 'line',
			source: SRC,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: {
				'line-color': '#ffffff',
				'line-width': ['case', ['get', 'highlight'], 10, 7],
				'line-opacity': 0.85
			}
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}collection-line`,
			type: 'line',
			source: SRC,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: {
				'line-color': ['get', 'color'],
				'line-width': ['case', ['get', 'highlight'], 6, 4]
			}
		});
	}

	$effect(() => {
		addLayers();
		const onStyle = () => {
			addLayers();
			(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(features());
		};
		map.on('style.load', onStyle);
		return () => map.off('style.load', onStyle);
	});

	$effect(() => {
		void [items, highlight, color];
		(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(features());
	});

	$effect(() => {
		if (!onclick) return;
		const layer = `${ROUTE_PREFIX}collection-line`;
		const click = (e: MapLayerMouseEvent) => {
			const id = e.features?.[0]?.properties?.id;
			if (typeof id === 'string') onclick(id);
		};
		const enter = () => (map.getCanvas().style.cursor = 'pointer');
		const leave = () => (map.getCanvas().style.cursor = '');
		map.on('click', layer, click);
		map.on('mouseenter', layer, enter);
		map.on('mouseleave', layer, leave);
		return () => {
			map.off('click', layer, click);
			map.off('mouseenter', layer, enter);
			map.off('mouseleave', layer, leave);
		};
	});
</script>
