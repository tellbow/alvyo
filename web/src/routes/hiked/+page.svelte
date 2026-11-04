<script lang="ts">
	import { LngLatBounds, type Map as MapLibreMap } from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import type { HikedItem } from '#lib/api/client.js';
	import { doneDate } from '#lib/done/done.js';
	import HikedLayers from '#lib/hiked/HikedLayers.svelte';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatDistance, formatDuration, formatHeight } from '#lib/planner/route.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>([]);
	let map = $state<MapLibreMap>();

	const items = $derived(data.hiked?.items ?? []);
	const totals = $derived(
		data.year ? data.hiked?.years?.find((y) => y.year === data.year) : data.hiked?.total
	);
	const href = (it: HikedItem) =>
		it.kind === 'journey'
			? resolve('/journeys/[id]', { id: it.id })
			: resolve('/routes/[id]', { id: it.id });
	const yearHref = (year?: number) => `${resolve('/hiked')}${year ? `?year=${year}` : ''}`;
	const chip = (on: boolean) =>
		`rounded-full px-3 py-1 text-sm ring-1 ${on ? 'bg-accent-soft font-semibold ring-accent' : 'ring-stone-300 hover:bg-stone-50'}`;

	// What is shown fills the view, whichever year is chosen.
	$effect(() => {
		if (!map) return;
		const bounds = new LngLatBounds();
		for (const it of items)
			for (const l of it.lines) for (const [lon, lat] of l) bounds.extend([lon, lat]);
		if (!bounds.isEmpty()) map.fitBounds(bounds, { padding: 48, maxZoom: 14, duration: 0 });
	});
</script>

<Seo title={m.hiked_title()} index={false} />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays onready={(mp) => (map = mp)} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}
			<HikedLayers {map} {items} onclick={(it) => goto(href(it))} />
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-96 md:flex-none md:border-t-0 md:border-l"
		data-testid="hiked-panel"
	>
		<div class="flex items-baseline justify-between">
			<h1 class="text-xl font-semibold">{m.hiked_title()}</h1>
			<a href={resolve('/routes')} class="text-sm text-accent-ink underline">{m.routes_title()}</a>
		</div>
		<p class="text-sm text-stone-500">{m.hiked_private()}</p>

		{#if !data.hiked}
			<p role="alert" class="text-sm text-red-700 dark:text-red-400">{m.error_generic()}</p>
		{:else if !data.hiked.years?.length}
			<p data-testid="hiked-empty">{m.hiked_empty()}</p>
		{:else}
			<nav class="flex flex-wrap gap-2" aria-label={m.hiked_years()}>
				<a
					href={yearHref()}
					data-sveltekit-noscroll
					class={chip(!data.year)}
					aria-current={!data.year ? 'page' : undefined}>{m.hiked_all()}</a
				>
				{#each data.hiked.years as y (y.year)}
					<a
						href={yearHref(y.year)}
						data-sveltekit-noscroll
						class={chip(data.year === y.year)}
						aria-current={data.year === y.year ? 'page' : undefined}
						data-testid="hiked-year">{y.year}</a
					>
				{/each}
			</nav>

			{#if totals}
				<dl class="grid grid-cols-2 gap-3 text-sm" data-testid="hiked-stats">
					{#each [[m.hiked_hikes(), String(totals.hikes)], [m.hiked_distance(), formatDistance(totals.distance_m)], [m.hiked_ascent(), formatHeight(totals.ascent_m)], [m.hiked_time(), formatDuration(totals.time_s)], [m.hiked_highest(), totals.highest_m > 0 ? formatHeight(totals.highest_m) : '–'], [m.hiked_longest(), formatDistance(totals.longest_m)]] as [label, value] (label)}
						<div>
							<dt class="text-stone-500">{label}</dt>
							<dd class="text-lg font-semibold">{value}</dd>
						</div>
					{/each}
				</dl>
			{/if}

			<ul class="flex flex-col divide-y divide-stone-200">
				{#each items as it, i (`${it.kind}-${it.id}-${it.on}-${i}`)}
					<li data-testid="hiked-item">
						<a href={href(it)} class="block py-2 hover:text-accent-ink">
							<span class="block font-medium">{it.title}</span>
							<span class="block text-sm text-stone-500">
								{doneDate(it.on)} · {formatDistance(it.distance_m)} · ↑&nbsp;{formatHeight(
									it.ascent_m
								)}
							</span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	</aside>
</main>
