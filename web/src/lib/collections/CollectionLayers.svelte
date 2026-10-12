<script lang="ts">
	import type { GeoJSONSource, MapLayerMouseEvent, Map as MapLibreMap } from 'maplibre-gl';
	import type { FeatureCollection, MultiLineString, Point } from 'geojson';
	import type { CollectionItem } from '#lib/api/client.js';
	import { stageColor } from '#lib/journeys/colors.js';
	import { OSM_ATTRIBUTION, ROUTE_PREFIX } from '#lib/map/styles.js';

	let {
		map,
		items,
		highlight,
		onclick,
		color = stageColor,
		starts = false
	}: {
		map: MapLibreMap;
		/** Collection items, or anything else with an id and lines (discovery). */
		items: Pick<CollectionItem, 'id' | 'lines'>[];
		highlight?: string;
		/** Called with the id of a clicked line. */
		onclick?: (id: string) => void;
		/** Colour of the i-th item's line; by default cycled like stages. */
		color?: (i: number) => string;
		/** A dot at each start, for items too short to see from afar. */
		starts?: boolean;
	} = $props();

	const SRC = `${ROUTE_PREFIX}collection`;
	const STARTS = `${ROUTE_PREFIX}collection-start`;

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

	function startFeatures(): FeatureCollection<Point> {
		return {
			type: 'FeatureCollection',
			features: items.flatMap((it, i) => {
				const at = it.lines[0]?.[0];
				if (!starts || !at) return [];
				return [
					{
						type: 'Feature' as const,
						properties: { id: it.id, color: color(i), highlight: it.id === highlight },
						geometry: { type: 'Point' as const, coordinates: at }
					}
				];
			})
		};
	}

	function addLayers() {
		if (map.getSource(SRC)) return;
		map.addSource(SRC, {
			type: 'geojson',
			data: { type: 'FeatureCollection', features: [] },
			attribution: OSM_ATTRIBUTION
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
		map.addSource(STARTS, { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
		// Only from afar; closer in the lines speak for themselves.
		map.addLayer({
			id: STARTS,
			type: 'circle',
			source: STARTS,
			maxzoom: 12,
			paint: {
				'circle-color': ['get', 'color'],
				'circle-radius': ['case', ['get', 'highlight'], 8, 6],
				'circle-stroke-color': '#ffffff',
				'circle-stroke-width': 2
			}
		});
	}

	function setData() {
		(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(features());
		(map.getSource(STARTS) as GeoJSONSource | undefined)?.setData(startFeatures());
	}

	$effect(() => {
		addLayers();
		const onStyle = () => {
			addLayers();
			setData();
		};
		map.on('style.load', onStyle);
		return () => map.off('style.load', onStyle);
	});

	$effect(() => {
		void [items, highlight, color, starts];
		setData();
	});

	$effect(() => {
		if (!onclick) return;
		const layers = [`${ROUTE_PREFIX}collection-line`, STARTS];
		const click = (e: MapLayerMouseEvent) => {
			const id = e.features?.[0]?.properties?.id;
			if (typeof id === 'string') onclick(id);
		};
		const enter = () => (map.getCanvas().style.cursor = 'pointer');
		const leave = () => (map.getCanvas().style.cursor = '');
		map.on('click', layers, click);
		map.on('mouseenter', layers, enter);
		map.on('mouseleave', layers, leave);
		return () => {
			map.off('click', layers, click);
			map.off('mouseenter', layers, enter);
			map.off('mouseleave', layers, leave);
		};
	});
</script>
