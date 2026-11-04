<script lang="ts">
	import { LngLatBounds, type Map as MapLibreMap } from 'maplibre-gl';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import HikedLayers from './HikedLayers.svelte';

	type Item = { lines: number[][][] };
	let { items, onclick }: { items: Item[]; onclick?: (index: number) => void } = $props();

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>([]);
	let map = $state<MapLibreMap>();

	// What is shown fills the view, whichever year is chosen.
	$effect(() => {
		if (!map) return;
		const bounds = new LngLatBounds();
		for (const it of items)
			for (const l of it.lines) for (const [lon, lat] of l) bounds.extend([lon, lat]);
		if (!bounds.isEmpty()) map.fitBounds(bounds, { padding: 48, maxZoom: 14, duration: 0 });
	});
</script>

<Map bind:base bind:overlays onready={(mp) => (map = mp)} />
<LayerSwitcher bind:base bind:overlays />
{#if map}
	<HikedLayers {map} {items} {onclick} />
{/if}
