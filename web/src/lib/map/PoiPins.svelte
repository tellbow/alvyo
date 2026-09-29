<script lang="ts">
	import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { poiText, type Poi } from './places';
	import { poiShown } from './poiKinds.svelte';
	import { ROUTE_PREFIX } from './styles';

	// What lies along the route, drawn with the kinds' icons (Map.svelte draws
	// them) and named in a popup; the kinds switched off in the layer menu stay off.
	let { map, lib, pois }: { map: MapLibreMap; lib: typeof MapLibre; pois: Poi[] } = $props();

	const ID = ROUTE_PREFIX + 'pois';

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
			if (map.getLayer(ID)) map.removeLayer(ID);
			if (map.getSource(ID)) map.removeSource(ID);
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
</script>
