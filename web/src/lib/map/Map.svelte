<script lang="ts">
	import { onMount } from 'svelte';
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import {
		CH_CENTER,
		OVERLAYS,
		OVERLAY_PREFIX,
		ROUTE_PREFIX,
		SWISSTOPO_ATTRIBUTION,
		baseStyle,
		keepOwnLayers,
		overlaySource,
		type BaseMapId,
		type OverlayId
	} from './styles';

	let {
		base = $bindable<BaseMapId>('landeskarte'),
		overlays = $bindable<OverlayId[]>(['wanderwege']),
		onready
	}: {
		base?: BaseMapId;
		overlays?: OverlayId[];
		/** Called once the first style is ready; `lib` is the maplibre-gl module. */
		onready?: (map: MapLibreMap, lib: typeof MapLibre) => void;
	} = $props();

	const STORAGE_KEY = 'odysgeh.map';
	const OPACITY: Record<OverlayId, number> = {
		wanderwege: 1,
		wanderland: 1,
		hangneigung: 0.6,
		relief: 0.5
	};

	let container: HTMLDivElement;
	let map = $state<MapLibreMap>();
	let layerIds = $state('');
	let shownBase: BaseMapId;
	// Layers can be added once a style's JSON is loaded (style.load), long
	// before its tiles are; isStyleLoaded() would wait for the tiles too.
	let styleReady = false;
	let pendingOverlays: OverlayId[] | undefined;

	onMount(() => {
		const saved = readSaved();
		if (saved) {
			base = saved.base;
			overlays = saved.overlays;
		}
		shownBase = base;
		let instance: MapLibreMap | undefined;
		let destroyed = false;

		// Vite must bundle the worker with its shared chunk (?worker&url); without
		// it vector tiles never load in production builds.
		Promise.all([
			import('maplibre-gl'),
			import('maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url')
		]).then(([ml, worker]) => {
			if (destroyed) return;
			ml.setWorkerUrl(worker.default);
			const m = new ml.Map({
				container,
				style: baseStyle(base, location.origin),
				center: saved?.center ?? CH_CENTER,
				zoom: saved?.zoom ?? 7.5,
				maxBounds: [
					[4.5, 45.0],
					[12.0, 48.6]
				],
				attributionControl: false
			});
			m.addControl(
				new ml.AttributionControl({ customAttribution: SWISSTOPO_ATTRIBUTION, compact: false })
			);
			m.addControl(new ml.NavigationControl(), 'top-right');
			m.addControl(new ml.GeolocateControl({ trackUserLocation: true }), 'top-right');
			m.addControl(new ml.ScaleControl({ unit: 'metric' }), 'bottom-left');
			m.on('styledata', () => {
				layerIds = m
					.getStyle()
					.layers.map((l) => l.id)
					.join(' ');
			});
			m.on('moveend', save);
			m.on('style.load', () => {
				styleReady = true;
				if (pendingOverlays) syncOverlays(m, pendingOverlays);
			});
			// style.load, not load: overlays and routes only need the style, not
			// a fully rendered first frame (slow for the vector base map).
			m.once('style.load', () => {
				map = m;
				onready?.(m, ml);
			});
			instance = m;
		});
		return () => {
			destroyed = true;
			instance?.remove();
		};
	});

	$effect(() => {
		if (!map || base === shownBase) return;
		shownBase = base;
		styleReady = false;
		map.setStyle(baseStyle(base, location.origin), { transformStyle: keepOwnLayers });
		save();
	});

	$effect(() => {
		if (!map) return;
		syncOverlays(map, [...overlays]);
		save();
	});

	/** Adds and removes overlay layers; waits while a new base style loads. */
	function syncOverlays(m: MapLibreMap, wanted: OverlayId[]) {
		if (!styleReady) {
			pendingOverlays = wanted;
			return;
		}
		pendingOverlays = undefined;
		for (const id of OVERLAYS) {
			const layerId = OVERLAY_PREFIX + id;
			const present = !!m.getLayer(layerId);
			if (wanted.includes(id) && !present) {
				if (!m.getSource(layerId)) m.addSource(layerId, overlaySource(id, location.origin));
				const beforeRoute = m.getStyle().layers.find((l) => l.id.startsWith(ROUTE_PREFIX))?.id;
				m.addLayer(
					{
						id: layerId,
						type: 'raster',
						source: layerId,
						paint: { 'raster-opacity': OPACITY[id] }
					},
					beforeRoute
				);
			} else if (!wanted.includes(id) && present) {
				m.removeLayer(layerId);
				m.removeSource(layerId);
			}
		}
	}

	type Saved = { base: BaseMapId; overlays: OverlayId[]; center: [number, number]; zoom: number };

	function readSaved(): Saved | undefined {
		try {
			return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? 'null') ?? undefined;
		} catch {
			return undefined;
		}
	}

	function save() {
		if (!map) return;
		const c = map.getCenter();
		const s: Saved = { base, overlays: [...overlays], center: [c.lng, c.lat], zoom: map.getZoom() };
		localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
	}
</script>

<!-- maplibre-gl.css makes the container position: relative, so it fills an
     absolutely positioned wrapper instead of being positioned itself. -->
<div class="absolute inset-0">
	<div bind:this={container} class="h-full w-full" data-testid="map" data-layers={layerIds}></div>
</div>
