<script lang="ts">
	import { officialLabel } from '#lib/official/official.js';
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import { onDestroy, untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type DiscoverItem, type Me } from '#lib/api/client.js';
	import CollectionLayers from '#lib/collections/CollectionLayers.svelte';
	import { stageColor } from '#lib/journeys/colors.js';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';

	let { user }: { user: Me | null } = $props();
	const pace = $derived(user?.speed_factor ?? 1);

	type Kind = '' | 'route' | 'journey';
	/** Hiking time filters in hours as shown (at the viewer's pace); 0: open. */
	const DURATIONS = {
		'': [0, 0],
		short: [0, 2],
		medium: [2, 4],
		long: [4, 6],
		xlong: [6, 0]
	} as const;
	type Duration = keyof typeof DURATIONS;

	const params = page.url.searchParams;
	const pick = <T extends string>(v: string | null, allowed: readonly T[]) =>
		allowed.find((a) => a === v) ?? allowed[0];
	let kind = $state<Kind>(pick(params.get('kind'), ['', 'route', 'journey'] as const));
	// The official Wanderland routes, those of people, or both.
	let origin = $state(pick(params.get('origin'), ['', 'only', 'none'] as const));
	let sac = $state(Math.min(Math.max(Number(params.get('sac')) || 0, 0), 6));
	let duration = $state<Duration>(
		pick(params.get('dur'), Object.keys(DURATIONS) as (keyof typeof DURATIONS)[])
	);

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let highlight = $state<string>();
	let items = $state<DiscoverItem[]>([]);
	let more = $state(false);
	let loading = $state(true);
	let failed = $state(false);

	function onready(mp: MapLibreMap) {
		const b = params.get('bbox')?.split(',').map(Number);
		if (b?.length === 4 && b.every(Number.isFinite)) {
			mp.fitBounds(
				[
					[b[0], b[1]],
					[b[2], b[3]]
				],
				{ duration: 0 }
			);
		}
		mp.on('moveend', () => {
			clearTimeout(timer);
			timer = setTimeout(search, 250);
		});
		map = mp;
	}

	let timer: ReturnType<typeof setTimeout>;
	onDestroy(() => {
		// Left for another page: a search still under way must not rewrite
		// that page's address.
		clearTimeout(timer);
		seq++;
	});

	let seq = 0;
	async function search() {
		if (!map) return;
		const bounds = map.getBounds();
		const bbox = [bounds.getWest(), bounds.getSouth(), bounds.getEast(), bounds.getNorth()]
			.map((v) => v.toFixed(4))
			.join(',');
		const [lo, hi] = DURATIONS[duration];
		const toSeconds = (h: number) => (h ? Math.round((h * 3600) / pace) : undefined);
		const n = ++seq;
		loading = true;
		const { data } = await api().GET('/discover', {
			params: {
				query: {
					bbox,
					kind: kind || undefined,
					official: origin || undefined,
					sac_max: sac || undefined,
					duration_min: toSeconds(lo),
					duration_max: toSeconds(hi)
				}
			}
		});
		if (n !== seq) return; // a newer search is under way
		loading = false;
		failed = !data;
		items = data?.items ?? [];
		more = data?.more ?? false;

		// The address describes the view, to share it or come back to it.
		const q = new URLSearchParams(
			Object.entries({ bbox, kind, origin, sac: sac ? String(sac) : '', dur: duration }).filter(
				([, v]) => v
			)
		);
		goto(`${resolve('/discover')}?${q}`, { shallow: true, replace: true, state: page.state });
	}

	$effect(() => {
		void [kind, origin, sac, duration, map];
		untrack(() => void search());
	});

	function href(it: DiscoverItem) {
		return it.kind === 'route'
			? resolve('/routes/[id]', { id: it.id })
			: resolve('/journeys/[id]', { id: it.id });
	}

	function open(id: string) {
		const it = items.find((i) => i.id === id);
		if (it) void goto(href(it));
	}
</script>

<Seo title={m.discover_title()} description={m.seo_discover_description()} image="/og.jpg" />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}
			<CollectionLayers {map} {items} {highlight} onclick={open} starts />
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-96 md:flex-none md:border-t-0 md:border-l"
		data-testid="discover-panel"
	>
		<h1 class="text-xl font-semibold">{m.discover_title()}</h1>

		<div class="flex flex-col gap-2 text-sm">
			<select
				bind:value={kind}
				aria-label={m.discover_kind()}
				class="rounded-md border border-stone-400 px-2 py-1.5"
			>
				<option value="">{m.discover_kind_all()}</option>
				<option value="route">{m.discover_kind_route()}</option>
				<option value="journey">{m.discover_kind_journey()}</option>
			</select>
			<select
				bind:value={origin}
				aria-label={m.discover_origin()}
				class="rounded-md border border-stone-400 px-2 py-1.5"
				data-testid="discover-origin"
			>
				<option value="">{m.discover_origin_all()}</option>
				<option value="only">{m.discover_origin_only()}</option>
				<option value="none">{m.discover_origin_none()}</option>
			</select>
			<div class="flex gap-2">
				<select
					bind:value={sac}
					aria-label={m.discover_sac()}
					class="flex-1 rounded-md border border-stone-400 px-2 py-1.5"
				>
					<option value={0}>{m.discover_sac_any()}</option>
					{#each [1, 2, 3, 4, 5, 6] as g (g)}
						<option value={g}>{m.discover_sac_max({ grade: `T${g}` })}</option>
					{/each}
				</select>
				<select
					bind:value={duration}
					aria-label={m.discover_duration()}
					class="flex-1 rounded-md border border-stone-400 px-2 py-1.5"
				>
					<option value="">{m.discover_duration_any()}</option>
					<option value="short">{m.discover_duration_short()}</option>
					<option value="medium">{m.discover_duration_medium()}</option>
					<option value="long">{m.discover_duration_long()}</option>
					<option value="xlong">{m.discover_duration_xlong()}</option>
				</select>
			</div>
			{#if duration && kind !== 'route'}
				<p class="text-xs text-stone-500">{m.discover_duration_hint()}</p>
			{/if}
		</div>

		{#if failed}
			<p role="alert" class="text-sm text-red-700 dark:text-red-400">{m.discover_failed()}</p>
		{:else if !loading && items.length === 0}
			<p class="text-sm text-stone-600">{m.discover_empty()}</p>
		{/if}

		<ol class="flex flex-col gap-2" data-testid="discover-results" aria-busy={loading}>
			{#each items as it, i (it.id)}
				<li
					class="rounded-md border border-stone-200 p-2 text-sm"
					data-testid="discover-item"
					onmouseenter={() => (highlight = it.id)}
					onmouseleave={() => (highlight = undefined)}
				>
					<div class="flex items-center gap-2">
						<span class="inline-block size-3 shrink-0 rounded-full" style:background={stageColor(i)}
						></span>
						<a href={href(it)} class="flex-1 font-medium hover:underline">{it.title}</a>
						<span class="text-xs text-stone-500"
							>{it.kind === 'route' ? m.collection_kind_route() : m.collection_kind_journey()}</span
						>
					</div>
					<div class="mt-1 flex items-center gap-2 text-xs text-stone-600 tabular-nums">
						{#if it.official}
							<span class="whitespace-nowrap" data-testid="discover-official"
								>{officialLabel(it.official)}</span
							>
						{:else}
							<a
								href={resolve('/u/[username]', { username: it.owner_username })}
								class="hover:underline">{m.shared_by({ user: it.owner_username })}</a
							>
						{/if}
						<span class="ml-auto"
							>{formatDistance(it.distance_m)} · {formatDuration(it.duration_s, pace)} · ↑&nbsp;{formatHeight(
								it.ascent_m
							)}</span
						>
						{#if it.sac_grade > 0}
							<span
								class="rounded px-1 font-semibold whitespace-nowrap"
								style:background={sacBackground(it.sac_grade)}
								style:color={sacInk(it.sac_grade)}>{formatSAC(it.sac_grade, it.sac_max)}</span
							>
						{/if}
					</div>
					{#if it.kind === 'journey'}
						<p class="mt-1 text-xs text-stone-500">
							{m.collection_stages({ n: it.stages })} · {m.discover_longest({
								time: formatDuration(it.longest_s, pace)
							})}
						</p>
					{/if}
				</li>
			{/each}
		</ol>

		{#if more}
			<p class="text-xs text-stone-500">{m.discover_more()}</p>
		{/if}
	</aside>
</main>
