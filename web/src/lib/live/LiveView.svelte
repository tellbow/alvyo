<script lang="ts">
	import type { Map as MapLibreMap, Marker } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { onDestroy } from 'svelte';
	import { api } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import CollectionLayers from '$lib/collections/CollectionLayers.svelte';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import { intlLocale } from '$lib/util/locale';

	type View = components['schemas']['View'];

	let { view: initial, token }: { view: View | null; token: string } = $props();

	// svelte-ignore state_referenced_locally
	let view = $state(initial);
	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib = $state<typeof MapLibre>();

	const time = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			weekday: 'short',
			hour: '2-digit',
			minute: '2-digit',
			timeZone: 'Europe/Zurich'
		})
	);
	const lines = $derived(
		view
			? [
					{ id: 'route', lines: view.route.length > 1 ? [view.route] : [] },
					{
						id: 'way',
						lines:
							view.way.length > 1 ? [view.way.map((p) => [p.lon, p.lat] as [number, number])] : []
					}
				]
			: []
	);

	// Asked again every minute while the hike goes on.
	const timer = setInterval(async () => {
		if (!view || view.ended_at) return;
		const { data } = await api().GET('/live/view/{token}', { params: { path: { token } } });
		if (data) view = data;
	}, 60_000);
	onDestroy(() => clearInterval(timer));

	function onready(mp: MapLibreMap, l: typeof MapLibre) {
		map = mp;
		lib = l;
		const pts: [number, number][] = [
			...(view?.route ?? []).map((c) => [c[0], c[1]] as [number, number]),
			...(view?.way ?? []).map((p) => [p.lon, p.lat] as [number, number])
		];
		if (view?.last) pts.push([view.last.lon, view.last.lat]);
		if (pts.length === 0) return;
		const b = pts.reduce((acc, c) => acc.extend(c), new l.LngLatBounds(pts[0], pts[0]));
		mp.fitBounds(b, { padding: 60, maxZoom: 15, duration: 0 });
	}

	let marker: Marker | undefined;
	$effect(() => {
		const last = view?.last;
		if (!map || !lib || !last) return;
		if (!marker) {
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			(el.firstElementChild as HTMLElement).className = 'live-dot';
			(el.firstElementChild as HTMLElement).dataset.testid = 'live-position';
			marker = new lib.Marker({ element: el }).setLngLat([last.lon, last.lat]).addTo(map);
		} else marker.setLngLat([last.lon, last.lat]);
	});
	onDestroy(() => marker?.remove());
</script>

<svelte:head
	><title>{view ? m.live_title({ hiker: view.hiker }) : m.live_gone()} · odysgeh</title
	></svelte:head
>

{#if !view}
	<main class="mx-auto max-w-xl px-4 py-12">
		<p data-testid="live-gone">{m.live_gone()}</p>
	</main>
{:else}
	<main class="flex min-h-0 flex-1 flex-col md:flex-row">
		<section class="relative min-h-80 flex-1">
			<Map bind:base bind:overlays {onready} />
			<LayerSwitcher bind:base bind:overlays />
			{#if map}
				<CollectionLayers {map} items={lines} color={(i) => (i === 0 ? '#a21caf' : '#2563eb')} />
			{/if}
		</section>
		<aside
			class="flex flex-col gap-3 border-l border-stone-200 bg-white p-4 text-sm md:w-96"
			data-testid="live-panel"
		>
			<h1 class="text-xl font-semibold">{m.live_title({ hiker: view.hiker })}</h1>
			<p class="font-medium">{view.title}</p>
			{#if view.ended_at}
				<p class="rounded-md bg-emerald-50 px-2 py-1 text-emerald-900" data-testid="live-status">
					{m.live_ended()} · {time.format(new Date(view.ended_at))}
				</p>
			{:else if view.overdue}
				<p
					class="rounded-md bg-red-50 px-2 py-1 font-medium text-red-900"
					data-testid="live-status"
				>
					{m.live_overdue({ time: time.format(new Date(view.expected_end)) })}
				</p>
				<p>{m.live_emergency()}</p>
			{:else}
				<p data-testid="live-status">
					{m.live_expected({ time: time.format(new Date(view.expected_end)) })}
				</p>
			{/if}
			{#if view.last}
				<p data-testid="live-last">{m.live_last({ time: time.format(new Date(view.last.at)) })}</p>
				<p class="text-xs text-stone-600">
					{m.live_coords()}: {view.last.lat.toFixed(5)}, {view.last.lon.toFixed(5)}
				</p>
			{:else}
				<p class="text-stone-500">{m.live_none()}</p>
			{/if}
		</aside>
	</main>
{/if}

<style>
	:global(.live-dot) {
		width: 18px;
		height: 18px;
		border-radius: 9999px;
		background: #2563eb;
		border: 3px solid #fff;
		box-shadow: 0 0 0 4px rgb(37 99 235 / 0.3);
	}
</style>
