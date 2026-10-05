<script lang="ts">
	import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { poiText, type Poi } from './places';
	import { poiShown } from './poiKinds.svelte';
	import { ROUTE_PREFIX } from './styles';

	// What lies along the route, drawn with the kinds' icons (Map.svelte draws
	// them) and named in a popup; the kinds switched off in the layer menu stay off.
	let {
		map,
		lib,
		pois,
		highlight = []
	}: {
		map: MapLibreMap;
		lib: typeof MapLibre;
		pois: Poi[];
		/** Points ringed, e.g. those of the list's row the pointer is on. */
		highlight?: number[][];
	} = $props();

	const ID = ROUTE_PREFIX + 'pois';
	const HIGHLIGHT = ROUTE_PREFIX + 'pois-highlight';

	// The layer first, then its events.
	$effect(() => {
		map.addSource(ID, {
			type: 'geojson',
			data: { type: 'FeatureCollection', features: [] },
			attribution: '© OpenStreetMap contributors'
		});
		map.addLayer({
			id: ID,
			type: 'symbol',
			source: ID,
			layout: {
				'icon-image': ['concat', 'poi-', ['get', 'kind']],
				'icon-size': ['interpolate', ['linear'], ['zoom'], 10, 0.7, 16, 1],
				'icon-allow-overlap': ['step', ['zoom'], false, 14, true]
			}
		});
		// Under the icons: a ring around the points of the row pointed at.
		map.addSource(HIGHLIGHT, {
			type: 'geojson',
			data: { type: 'FeatureCollection', features: [] }
		});
		map.addLayer(
			{
				id: HIGHLIGHT,
				type: 'circle',
				source: HIGHLIGHT,
				paint: {
					'circle-radius': 16,
					'circle-color': '#f28a48',
					'circle-opacity': 0.35,
					'circle-stroke-color': '#f28a48',
					'circle-stroke-width': 2
				}
			},
			ID
		);
		const click = (e: MapLayerMouseEvent) => {
			const f = e.features?.[0];
			if (!f || f.geometry.type !== 'Point' || e.defaultPrevented) return;
			e.preventDefault();
			const p = f.properties as { kind: Poi['kind']; name: string; ele: number };
			const [title, detail] = poiText({ kind: p.kind, name: p.name, ele: p.ele || undefined });
			// MapLibre's popups stay white in dark mode: fixed light-mode colours.
			const box = document.createElement('div');
			box.className = 'text-sm text-[#14201a]';
			box.dataset.testid = 'poi-popup';
			const t = document.createElement('p');
			t.className = 'font-medium';
			t.textContent = title;
			const d = document.createElement('p');
			d.className = 'text-[#56645c]';
			d.textContent = detail;
			box.append(t, d);
			new lib.Popup({ maxWidth: '260px' })
				.setLngLat(f.geometry.coordinates as [number, number])
				.setDOMContent(box)
				.addTo(map);
		};
		const enter = () => (map.getCanvas().style.cursor = 'pointer');
		const leave = () => (map.getCanvas().style.cursor = '');
		map.on('click', ID, click);
		map.on('mouseenter', ID, enter);
		map.on('mouseleave', ID, leave);
		return () => {
			map.off('click', ID, click);
			map.off('mouseenter', ID, enter);
			map.off('mouseleave', ID, leave);
			for (const id of [HIGHLIGHT, ID]) {
				if (map.getLayer(id)) map.removeLayer(id);
				if (map.getSource(id)) map.removeSource(id);
			}
		};
	});

	// The points of the kinds switched on.
	$effect(() => {
		(map.getSource(ID) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: pois
				.filter((p) => poiShown.kinds.includes(p.kind))
				.map((p) => ({
					type: 'Feature',
					geometry: { type: 'Point', coordinates: p.at },
					properties: { kind: p.kind, name: p.name, ele: p.ele ?? 0 }
				}))
		});
	});

	// The ringed points; the map moves to them when none is in view.
	$effect(() => {
		(map.getSource(HIGHLIGHT) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: highlight.map((at) => ({
				type: 'Feature',
				geometry: { type: 'Point', coordinates: at },
				properties: {}
			}))
		});
		const bounds = map.getBounds();
		if (highlight.length > 0 && !highlight.some((at) => bounds.contains([at[0], at[1]]))) {
			map.easeTo({ center: [highlight[0][0], highlight[0][1]] });
		}
	});
</script>
