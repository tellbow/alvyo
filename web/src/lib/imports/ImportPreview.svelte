<script lang="ts">
	import type { Map as MapLibreMap, MapMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import CollectionLayers from '#lib/collections/CollectionLayers.svelte';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import ElevationProfile from '#lib/planner/ElevationProfile.svelte';
	import type { Profile3 } from '#lib/planner/route.js';

	// What a file holds, before anything is saved (feedback issue 47): its
	// tracks or the stages proposed, on the map in the stages' colours, and
	// their elevation profile.
	let {
		lines,
		profile,
		breaks = [],
		onpick
	}: {
		/** [lon, lat, elevation] per point, one line per track or stage */
		lines: number[][][];
		profile: Profile3;
		breaks?: number[];
		/** A tap on line k of the map or its part of the profile. */
		onpick?: (k: number, lon: number, lat: number) => void;
	} = $props();

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib: typeof MapLibre | undefined;
	let hover = $state<number>();

	const items = $derived(
		lines.map((l, i) => ({ id: String(i), lines: [l.map((c) => [c[0], c[1]])] }))
	);
	// A file without heights (beyond the border) has no profile worth showing.
	const heights = $derived(profile.coordinates.some((c) => c[2] !== 0));

	function fit() {
		const pts = lines.flat();
		if (!map || !lib || pts.length === 0) return;
		const b = pts.reduce(
			(acc, c) => acc.extend([c[0], c[1]]),
			new lib.LngLatBounds([pts[0][0], pts[0][1]], [pts[0][0], pts[0][1]])
		);
		map.fitBounds(b, { padding: 30, duration: 0, maxZoom: 14 });
	}

	function onready(mp: MapLibreMap, l: typeof MapLibre) {
		map = mp;
		lib = l;
		fit();
	}

	$effect(() => {
		void lines;
		fit();
	});

	const TAP_PX = 24;

	/** The tap on the map, if near the line: its nearest point. */
	function tapped(e: MapMouseEvent) {
		let best = TAP_PX;
		let found: [number, number[]] | undefined;
		lines.forEach((l, k) => {
			for (const c of l) {
				const d = map!.project([c[0], c[1]]).dist(e.point);
				if (d < best) {
					best = d;
					found = [k, c];
				}
			}
		});
		if (found) onpick?.(found[0], found[1][0], found[1][1]);
	}

	$effect(() => {
		if (!map || !onpick) return;
		const mp = map;
		mp.on('click', tapped);
		return () => mp.off('click', tapped);
	});

	function profileTap(i: number) {
		const c = profile.coordinates[i];
		onpick?.(
			breaks.findLastIndex((b) => b <= i),
			c[0],
			c[1]
		);
	}
</script>

<div class="mt-3 flex flex-col gap-2" data-testid="import-preview">
	<div class="relative h-64 overflow-hidden rounded-md border border-stone-200 sm:h-80">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}<CollectionLayers {map} {items} />{/if}
	</div>
	{#if heights}
		<ElevationProfile line={profile} {breaks} bind:hover onpick={onpick ? profileTap : undefined} />
	{/if}
</div>
