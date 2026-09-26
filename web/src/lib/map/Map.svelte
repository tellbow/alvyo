<script lang="ts">
	import { onMount } from 'svelte';
	import type { GeoJSONSource, Map as MapLibreMap, MapLayerMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { api, type Pin } from '$lib/api/client';
	import { placeDetail } from '$lib/journeys/places';
	import { m as msg } from '$lib/paraglide/messages';
	import { PLACE_OVERLAYS, placeFeatures, placeKinds, webLink } from './places';
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
		type OverlayId,
		type PlaceOverlayId,
		type RasterOverlayId
	} from './styles';
	import { TILE_PROTOCOL, tileLoader } from './tiles';

	let {
		base = $bindable<BaseMapId>('landeskarte'),
		overlays = $bindable<OverlayId[]>(['wanderwege']),
		onready,
		placeAction
	}: {
		base?: BaseMapId;
		overlays?: OverlayId[];
		/** Called once the first style is ready; `lib` is the maplibre-gl module. */
		onready?: (map: MapLibreMap, lib: typeof MapLibre) => void;
		/** A button in the popup of a hut or accommodation. */
		placeAction?: { label: string; run: (p: Pin) => void };
	} = $props();

	const STORAGE_KEY = 'alvyo.map';
	const OPACITY: Record<RasterOverlayId, number> = {
		wanderwege: 1,
		wanderland: 1,
		hangneigung: 0.6,
		wildruhezonen: 0.7,
		jagdbanngebiete: 0.6,
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

	// Huts and accommodation share one source, one layer per overlay.
	const PLACES = OVERLAY_PREFIX + 'places';
	const placeLayer = (id: PlaceOverlayId) => OVERLAY_PREFIX + id;
	const PLACE_LAYERS = (Object.keys(PLACE_OVERLAYS) as PlaceOverlayId[]).map(placeLayer);
	let places = placeFeatures([]);
	let placesAsked = 0;
	let placesTimer: ReturnType<typeof setTimeout> | undefined;

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
			ml.addProtocol(TILE_PROTOCOL, tileLoader());
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
			m.on('moveend', loadPlaces);
			// Registered before the pages' own click handlers, which skip a
			// click prevented here.
			m.on('click', PLACE_LAYERS, (e: MapLayerMouseEvent) => {
				const f = e.features?.[0];
				if (!f || f.geometry.type !== 'Point') return;
				e.preventDefault();
				const p = f.properties as Pin;
				const [lon, lat] = f.geometry.coordinates;
				const popup = new ml.Popup({ maxWidth: '260px' }).setLngLat([lon, lat]);
				popup.setDOMContent(placePopup({ ...p, lon, lat }, () => popup.remove())).addTo(m);
			});
			for (const id of PLACE_LAYERS) {
				m.on('mouseenter', id, () => (m.getCanvas().style.cursor = 'pointer'));
				m.on('mouseleave', id, () => (m.getCanvas().style.cursor = ''));
			}
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
			clearTimeout(placesTimer);
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
		loadPlaces();
	});

	/** Adds and removes overlay layers; waits while a new base style loads. */
	function syncOverlays(m: MapLibreMap, wanted: OverlayId[]) {
		if (!styleReady) {
			pendingOverlays = wanted;
			return;
		}
		pendingOverlays = undefined;
		// Raster overlays go below the places, places below the routes.
		const below = (layers: string[]) =>
			m.getStyle().layers.find((l) => l.id.startsWith(ROUTE_PREFIX) || layers.includes(l.id))?.id;
		for (const id of OVERLAYS) {
			const layerId = OVERLAY_PREFIX + id;
			const present = !!m.getLayer(layerId);
			if (id in PLACE_OVERLAYS) {
				const o = PLACE_OVERLAYS[id as PlaceOverlayId];
				if (wanted.includes(id) && !present) {
					if (!m.getSource(PLACES))
						m.addSource(PLACES, {
							type: 'geojson',
							data: places,
							attribution: '© OpenStreetMap contributors'
						});
					m.addLayer(
						{
							id: layerId,
							type: 'circle',
							source: PLACES,
							minzoom: o.minZoom,
							filter: ['in', ['get', 'kind'], ['literal', o.kinds]],
							paint: {
								'circle-radius': ['interpolate', ['linear'], ['zoom'], 8, 4, 14, 7],
								'circle-color': [
									'match',
									['get', 'kind'],
									'hut',
									'#b91c1c',
									'campsite',
									'#15803d',
									'#1d4ed8' // hotel
								],
								'circle-stroke-color': '#fff',
								'circle-stroke-width': 1.5
							}
						},
						below([])
					);
				} else if (!wanted.includes(id) && present) m.removeLayer(layerId);
			} else if (wanted.includes(id) && !present) {
				if (!m.getSource(layerId))
					m.addSource(layerId, overlaySource(id as RasterOverlayId, location.origin));
				m.addLayer(
					{
						id: layerId,
						type: 'raster',
						source: layerId,
						paint: { 'raster-opacity': OPACITY[id as RasterOverlayId] }
					},
					below(PLACE_LAYERS)
				);
			} else if (!wanted.includes(id) && present) {
				m.removeLayer(layerId);
				m.removeSource(layerId);
			}
		}
		if (!PLACE_LAYERS.some((id) => m.getLayer(id)) && m.getSource(PLACES)) m.removeSource(PLACES);
	}

	/** Fetches the places of the view once the map rests; later answers win. */
	function loadPlaces() {
		clearTimeout(placesTimer);
		placesTimer = setTimeout(async () => {
			if (!map) return;
			const asked = ++placesAsked;
			const kinds = placeKinds(overlays, map.getZoom());
			let pins: Pin[] = [];
			if (kinds.length) {
				const b = map.getBounds();
				const bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].map((v) =>
					v.toFixed(5)
				);
				const { data } = await api().GET('/places/in-view', {
					params: { query: { bbox: bbox.join(','), kind: kinds } }
				});
				if (asked !== placesAsked || !data) return; // offline: keep what is shown
				pins = data.places;
			}
			places = placeFeatures(pins);
			(map.getSource(PLACES) as GeoJSONSource | undefined)?.setData(places);
		}, 300);
	}

	/** Name, kind, website and the page's action; built without HTML strings. */
	function placePopup(p: Pin, close: () => void): HTMLElement {
		const el = (tag: string, cls: string, text = '') => {
			const e = document.createElement(tag);
			e.className = cls;
			e.textContent = text;
			return e;
		};
		// MapLibre's popups stay white in dark mode: fixed light-mode colours.
		const box = el('div', 'text-sm text-[#14201a]');
		box.dataset.testid = 'place-popup';
		box.append(el('p', 'font-medium', p.name), el('p', 'text-[#56645c]', placeDetail(p)));
		const href = webLink(p.website);
		if (href) {
			const a = el(
				'a',
				'text-[#b4531d] underline',
				`${msg.map_place_website()} ↗`
			) as HTMLAnchorElement;
			a.href = href;
			a.target = '_blank';
			a.rel = 'noopener noreferrer nofollow';
			box.append(a);
		}
		if (placeAction) {
			const action = placeAction;
			const b = el(
				'button',
				'mt-2 block rounded-md bg-[#f28a48] px-2 py-1 font-medium text-on-accent',
				action.label
			);
			(b as HTMLButtonElement).type = 'button';
			b.onclick = () => {
				action.run(p);
				close();
			};
			box.append(b);
		}
		return box;
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
		try {
			localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
		} catch {
			// storage blocked or full: the view is not remembered
		}
	}
</script>

<!-- maplibre-gl.css makes the container position: relative, so it fills an
     absolutely positioned wrapper instead of being positioned itself. -->
<div class="absolute inset-0">
	<div bind:this={container} class="h-full w-full" data-testid="map" data-layers={layerIds}></div>
</div>
