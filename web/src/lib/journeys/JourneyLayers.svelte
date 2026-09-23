<script lang="ts">
	import type { GeoJSONSource, Map as MapLibreMap, Marker } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import type { FeatureCollection, LineString } from 'geojson';
	import type { Journey } from '$lib/api/client';
	import { ROUTE_PREFIX } from '$lib/map/styles';
	import { stageColor } from './colors';

	let {
		map,
		lib,
		journey,
		hover
	}: { map: MapLibreMap; lib: typeof MapLibre; journey: Journey; hover?: [number, number] } =
		$props();

	const SRC = `${ROUTE_PREFIX}journey`;
	const HOVER = `${ROUTE_PREFIX}journey-hover`;
	const empty = { type: 'FeatureCollection' as const, features: [] };

	/** Stage lines plus dashed connectors where consecutive stages do not meet. */
	function features(): FeatureCollection<LineString> {
		const out: FeatureCollection<LineString> = { type: 'FeatureCollection', features: [] };
		let prevEnd: number[] | undefined;
		journey.stage_list.forEach((s, i) => {
			if (!s.route) return;
			if (prevEnd && s.gap && s.gap.status !== 'ok') {
				out.features.push({
					type: 'Feature',
					properties: { gap: true },
					geometry: { type: 'LineString', coordinates: [prevEnd, s.route.start] }
				});
			}
			out.features.push({
				type: 'Feature',
				properties: { gap: false, color: stageColor(i) },
				geometry: { type: 'LineString', coordinates: s.route.line }
			});
			prevEnd = s.route.end;
		});
		return out;
	}

	function addLayers() {
		if (map.getSource(SRC)) return;
		map.addSource(SRC, {
			type: 'geojson',
			data: empty,
			attribution: '© OpenStreetMap contributors'
		});
		map.addSource(HOVER, { type: 'geojson', data: empty });
		map.addLayer({
			id: `${ROUTE_PREFIX}journey-casing`,
			type: 'line',
			source: SRC,
			filter: ['!', ['get', 'gap']],
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': '#ffffff', 'line-width': 8, 'line-opacity': 0.85 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}journey-line`,
			type: 'line',
			source: SRC,
			filter: ['!', ['get', 'gap']],
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': ['get', 'color'], 'line-width': 4.5 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}journey-gap`,
			type: 'line',
			source: SRC,
			filter: ['get', 'gap'],
			paint: { 'line-color': '#57534e', 'line-width': 2.5, 'line-dasharray': [1, 2] }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}journey-hover`,
			type: 'circle',
			source: HOVER,
			paint: {
				'circle-radius': 6,
				'circle-color': '#1c1917',
				'circle-stroke-color': '#ffffff',
				'circle-stroke-width': 2
			}
		});
	}

	function render() {
		(map.getSource(SRC) as GeoJSONSource | undefined)?.setData(features());
		(map.getSource(HOVER) as GeoJSONSource | undefined)?.setData(
			hover ? { type: 'Point', coordinates: hover } : empty
		);
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
		void [journey, hover];
		render();
	});

	// Numbered stage starts. Rebuilt when the journey changes (a few markers).
	$effect(() => {
		const markers: Marker[] = [];
		journey.stage_list.forEach((s, i) => {
			if (!s.route) return;
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			const dot = el.firstElementChild as HTMLElement;
			dot.className = 'stage-marker';
			dot.style.background = stageColor(i);
			dot.textContent = String(i + 1);
			dot.dataset.testid = 'stage-marker';
			markers.push(
				new lib.Marker({ element: el }).setLngLat(s.route.start as [number, number]).addTo(map)
			);
		});
		return () => markers.forEach((m) => m.remove());
	});
</script>

<style>
	:global(.stage-marker) {
		width: 22px;
		height: 22px;
		border-radius: 9999px;
		border: 2px solid #fff;
		box-shadow: 0 1px 3px rgb(0 0 0 / 0.4);
		color: #fff;
		font:
			700 11px/18px system-ui,
			sans-serif;
		text-align: center;
	}
</style>
