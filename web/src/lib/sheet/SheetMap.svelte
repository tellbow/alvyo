<script lang="ts">
	import { ROUTE_COLOR } from '$lib/planner/colors';
	import { onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { m } from '$lib/paraglide/messages';
	import { baseStyle, overlaySource } from '$lib/map/styles';
	import { TILE_PROTOCOL, tileLoader } from '$lib/map/tiles';

	// The line on the national map with the hiking trails, drawn once and
	// kept as an image: a WebGL canvas does not print reliably. Drawn at
	// RENDER × RENDER × 3 / 8 pixels and shown smaller: about a zoom level more
	// detail, sharp on paper; swisstopo's maps at the lower zoom are blown-up
	// small-scale maps.
	let { line }: { line: number[][] } = $props();
	const RENDER = 1600;
	/** Line widths for the picture shown at about a third of its size. */
	const px = (n: number) => n * 2.2;

	let container: HTMLDivElement;
	let image = $state<string>();

	onMount(() => {
		let destroyed = false;
		let remove = () => {};
		Promise.all([
			import('maplibre-gl'),
			import('maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url')
		]).then(([ml, worker]) => {
			if (destroyed || line.length < 2) return;
			ml.setWorkerUrl(worker.default);
			ml.addProtocol(TILE_PROTOCOL, tileLoader());
			const bounds = line.reduce(
				(b, c) => b.extend([c[0], c[1]]),
				new ml.LngLatBounds([line[0][0], line[0][1]], [line[0][0], line[0][1]])
			);
			const map = new ml.Map({
				container,
				style: baseStyle('landeskarte', location.origin),
				bounds,
				fitBoundsOptions: { padding: px(30), maxZoom: 16 },
				interactive: false,
				attributionControl: false,
				pixelRatio: 1,
				canvasContextAttributes: { preserveDrawingBuffer: true }
			});
			remove = () => map.remove();
			map.once('style.load', () => {
				map.addSource('wanderwege', overlaySource('wanderwege', location.origin));
				map.addLayer({ id: 'wanderwege', type: 'raster', source: 'wanderwege' });
				const coordinates = line.map((c) => [c[0], c[1]]);
				map.addSource('line', {
					type: 'geojson',
					data: {
						type: 'FeatureCollection',
						features: [
							{ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates } },
							...[coordinates[0], coordinates.at(-1)!].map((c, i) => ({
								type: 'Feature' as const,
								properties: { end: i },
								geometry: { type: 'Point' as const, coordinates: c }
							}))
						]
					}
				});
				map.addLayer({
					id: 'casing',
					type: 'line',
					source: 'line',
					layout: { 'line-join': 'round', 'line-cap': 'round' },
					paint: { 'line-color': '#ffffff', 'line-width': px(7), 'line-opacity': 0.85 }
				});
				map.addLayer({
					id: 'line',
					type: 'line',
					source: 'line',
					layout: { 'line-join': 'round', 'line-cap': 'round' },
					paint: { 'line-color': ROUTE_COLOR, 'line-width': px(4) }
				});
				map.addLayer({
					id: 'ends',
					type: 'circle',
					source: 'line',
					filter: ['==', ['geometry-type'], 'Point'],
					paint: {
						'circle-radius': px(6),
						'circle-color': ['match', ['get', 'end'], 0, '#15803d', '#b91c1c'],
						'circle-stroke-color': '#ffffff',
						'circle-stroke-width': px(2)
					}
				});
				map.once('idle', () => {
					image = map.getCanvas().toDataURL('image/png');
					remove();
				});
			});
		});
		return () => {
			destroyed = true;
			remove();
		};
	});
</script>

<figure
	class="relative aspect-[8/3] w-full break-inside-avoid overflow-hidden rounded-md border border-stone-300"
>
	<div
		bind:this={container}
		class="invisible absolute top-0 left-0"
		style:width="{RENDER}px"
		style:height="{(RENDER * 3) / 8}px"
	></div>
	{#if image}
		<img
			src={image}
			alt={m.sheet_map()}
			class="absolute inset-0 size-full"
			data-testid="sheet-map"
		/>
	{/if}
	<figcaption class="absolute right-0 bottom-0 bg-white/80 px-1 text-[9px] text-[#56645c]">
		© swisstopo
	</figcaption>
</figure>
