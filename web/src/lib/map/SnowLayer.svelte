<script lang="ts">
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import { api, type Snow } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { intlLocale } from '#lib/util/locale.js';
	import { OVERLAY_PREFIX, ROUTE_PREFIX } from './styles';

	let {
		map,
		below = false
	}: {
		map: MapLibreMap;
		/** The rain's box is shown too: this one goes below it. */
		below?: boolean;
	} = $props();

	const ID = OVERLAY_PREFIX + 'snow';
	// Snow goes below the rain, the places and the routes.
	const ABOVE = ['precip', 'huts', 'lodging', 'pois'].map((id) => OVERLAY_PREFIX + id);

	let cover = $state<Snow>();
	let open = $state(false);

	// A new day comes once a day; an hour is often enough.
	$effect(() => {
		let stopped = false;
		async function load() {
			const { data } = await api().GET('/weather/snow');
			if (!stopped && data) cover = data;
		}
		load();
		const timer = setInterval(load, 60 * 60_000);
		return () => {
			stopped = true;
			clearInterval(timer);
		};
	});

	$effect(() => {
		const c = cover;
		if (!c?.tiles) return;
		const tiles = location.origin + c.tiles;
		const show = () => {
			if (map.getLayer(ID)) map.removeLayer(ID);
			if (map.getSource(ID)) map.removeSource(ID);
			map.addSource(ID, {
				type: 'raster',
				tiles: [tiles],
				tileSize: 256,
				minzoom: c.minzoom,
				maxzoom: c.maxzoom,
				bounds: [c.bounds.west, c.bounds.south, c.bounds.east, c.bounds.north],
				attribution: `<a href="https://land.copernicus.eu/en/products/snow" target="_blank" rel="noopener">${c.attribution}</a>`
			});
			const next = map
				.getStyle()
				.layers.find((l) => l.id.startsWith(ROUTE_PREFIX) || ABOVE.includes(l.id))?.id;
			map.addLayer({ id: ID, type: 'raster', source: ID }, next);
		};
		try {
			show();
		} catch {
			map.once('style.load', show); // a new base map is loading
		}
	});

	$effect(() => () => {
		try {
			if (map.getLayer(ID)) map.removeLayer(ID);
			if (map.getSource(ID)) map.removeSource(ID);
		} catch {
			// the map is gone
		}
	});

	const day = (d: string) =>
		new Intl.DateTimeFormat(intlLocale(), {
			day: 'numeric',
			month: 'long',
			timeZone: 'UTC'
		}).format(new Date(`${d}T00:00:00Z`));
</script>

<div
	class="absolute left-2 z-10 w-72 max-w-[calc(100%-4.5rem)] rounded-md bg-surface/95 p-2 text-xs shadow ring-1 ring-stone-300 {below
		? 'top-36'
		: 'top-12'}"
	data-testid="snow"
>
	{#if cover && !cover.date}
		<p>{m.snow_none()}</p>
	{:else if cover?.date}
		<div class="flex items-start justify-between gap-2">
			<p class="font-medium" data-testid="snow-date">{m.snow_date({ date: day(cover.date) })}</p>
			<button
				type="button"
				class="-m-1 rounded px-1 text-sm text-stone-600 hover:bg-stone-100"
				aria-expanded={open}
				aria-label={open ? m.snow_less() : m.snow_more()}
				title={open ? m.snow_less() : m.snow_more()}
				data-testid="snow-more"
				onclick={() => (open = !open)}>{open ? '▴' : 'ⓘ'}</button
			>
		</div>
		<!-- Each colour with its name: 15, 50 and 90 % snow. -->
		<div class="mt-1.5 grid grid-cols-3 gap-0.5">
			{#each cover.legend as l, i (l.from)}
				<div>
					<span class="block h-2 rounded-sm" style:background={l.color}></span>
					<span class="text-stone-600">{[m.snow_patchy, m.snow_mostly, m.snow_full][i]?.()}</span>
				</div>
			{/each}
		</div>
		<!-- Small at first: what it does not show and the source behind a tap. -->
		{#if open}
			<p class="mt-1">{m.snow_hint()}</p>
			<p class="mt-1 text-stone-500">
				{m.snow_note()} ·
				<a
					href="https://land.copernicus.eu/en/products/snow"
					target="_blank"
					rel="noopener"
					class="underline">Copernicus (EU)</a
				>
			</p>
		{/if}
	{/if}
</div>
