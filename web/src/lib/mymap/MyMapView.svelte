<script lang="ts">
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import { onDestroy, onMount, untrack } from 'svelte';
	import { goto, replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me, type MyMapItem } from '$lib/api/client';
	import CollectionLayers from '$lib/collections/CollectionLayers.svelte';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import { SAC_COLOR } from '$lib/planner/colors';
	import { formatDistance, formatDuration, formatSAC } from '$lib/planner/route';
	import TagChips from '$lib/tags/TagChips.svelte';
	import { sameTag } from '$lib/tags/tags';
	import { apiQuery, KINDS, readFilters, writeFilters, type Kind } from './filters';

	let { user }: { user: Me } = $props();
	const pace = $derived(user.speed_factor ?? 1);

	const KIND_COLOR: Record<Kind, string> = {
		route: '#a21caf',
		journey: '#2563eb',
		hike: '#0f766e'
	};
	const kindLabel = (k: Kind) =>
		k === 'route'
			? m.mymap_kind_route()
			: k === 'journey'
				? m.mymap_kind_journey()
				: m.mymap_kind_hike();
	const itemKind = (k: Kind) =>
		k === 'route'
			? m.collection_kind_route()
			: k === 'journey'
				? m.collection_kind_journey()
				: m.mymap_hiked();

	const params = page.url.searchParams;
	let filters = $state(readFilters(params));
	let myTags = $state<string[]>([]);
	// Tags from the address the user no longer has stay choosable.
	const tagChoices = $derived([
		...myTags,
		...filters.tags.filter((t) => !myTags.some((x) => sameTag(x, t)))
	]);

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let highlight = $state<string>();
	let items = $state<MyMapItem[]>([]);
	let more = $state(false);
	let loading = $state(true);
	let failed = $state(false);

	const color = $derived((i: number) => {
		const it = items[i];
		if (!it) return '#a8a29e';
		return filters.color === 'sac'
			? (SAC_COLOR[`T${it.sac_grade}`] ?? '#a8a29e')
			: KIND_COLOR[it.kind as Kind];
	});

	onMount(async () => {
		const { data } = await api().GET('/me/tags');
		myTags = data?.tags.map((t) => t.tag) ?? [];
	});

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
		const f = $state.snapshot(filters);
		const n = ++seq;
		loading = true;
		const { data } = await api().GET('/me/map', {
			params: { query: { bbox, ...apiQuery(f, pace) } }
		});
		if (n !== seq) return; // a newer search is under way
		loading = false;
		failed = !data;
		items = data?.items ?? [];
		more = data?.more ?? false;
		// The address keeps the view and the filters, to bookmark them.
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- resolve() gives the path; only the query is added
		replaceState(`${resolve('/routes/map')}?${writeFilters(f, bbox)}`, page.state);
	}

	$effect(() => {
		void [JSON.stringify(filters), map];
		untrack(() => void search());
	});

	function toggle<T>(list: T[], v: T): T[] {
		return list.includes(v) ? list.filter((x) => x !== v) : [...list, v];
	}

	/** A number field's value: undefined when empty or not above 0. */
	const bound = (v: string) => (Number(v) > 0 ? Number(v) : undefined);

	function reset() {
		filters = { ...readFilters(new URLSearchParams()), color: filters.color };
	}

	function href(it: MyMapItem) {
		return it.kind === 'journey'
			? resolve('/journeys/[id]', { id: it.id })
			: resolve('/routes/[id]', { id: it.id });
	}

	function open(id: string) {
		const it = items.find((i) => i.id === id);
		if (it) void goto(href(it));
	}
</script>

<svelte:head><title>{m.mymap_title()} · odysgeh</title></svelte:head>

<main class="flex min-h-0 flex-1">
	<section class="relative flex-1">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}
			<CollectionLayers {map} {items} {highlight} {color} onclick={open} />
		{/if}
	</section>

	<aside
		class="flex w-96 flex-col gap-4 overflow-y-auto border-l border-stone-200 bg-white p-4"
		data-testid="mymap-panel"
	>
		<div class="flex items-baseline justify-between">
			<h1 class="text-xl font-semibold">{m.mymap_title()}</h1>
			<a href={resolve('/routes')} class="text-sm text-emerald-800 underline">{m.routes_title()}</a>
		</div>

		<div class="flex flex-col gap-3 text-sm">
			<fieldset>
				<legend class="mb-1 font-medium">{m.mymap_kinds()}</legend>
				<div class="flex flex-wrap gap-3">
					{#each KINDS as k (k)}
						<label class="flex items-center gap-1">
							<input
								type="checkbox"
								checked={filters.kinds.includes(k)}
								onchange={() => (filters.kinds = toggle(filters.kinds, k))}
							/>
							<span class="inline-block size-2.5 rounded-full" style:background={KIND_COLOR[k]}
							></span>
							{kindLabel(k)}
						</label>
					{/each}
				</div>
			</fieldset>

			{#if tagChoices.length > 0}
				<fieldset data-testid="mymap-tags">
					<legend class="mb-1 font-medium">{m.mymap_tags()}</legend>
					<div class="flex flex-wrap gap-1">
						{#each tagChoices as t (t)}
							{@const on = filters.tags.some((x) => sameTag(x, t))}
							<button
								type="button"
								aria-pressed={on}
								class="rounded-full px-2 py-0.5 text-xs {on
									? 'bg-emerald-700 text-white'
									: 'bg-stone-100 text-stone-700 hover:bg-stone-200'}"
								onclick={() =>
									(filters.tags = on
										? filters.tags.filter((x) => !sameTag(x, t))
										: [...filters.tags, t])}>{t}</button
							>
						{/each}
					</div>
				</fieldset>
			{/if}

			{#each [{ key: 'distance', label: m.mymap_distance(), step: '0.5' }, { key: 'duration', label: m.mymap_duration(), step: '0.5' }] as const as r (r.key)}
				<fieldset class="flex items-center gap-2">
					<legend class="mb-1 font-medium">{r.label}</legend>
					{#each [0, 1] as end (end)}
						<input
							type="number"
							min="0"
							step={r.step}
							inputmode="decimal"
							class="w-20 rounded-md border border-stone-300 px-2 py-1"
							aria-label="{r.label} {end === 0 ? m.mymap_from() : m.mymap_to()}"
							placeholder={end === 0 ? m.mymap_from() : m.mymap_to()}
							value={filters[r.key][end] ?? ''}
							onchange={(e) => {
								const next = [...filters[r.key]] as [number | undefined, number | undefined];
								next[end] = bound(e.currentTarget.value);
								filters[r.key] = next;
							}}
						/>
						{#if end === 0}<span>–</span>{/if}
					{/each}
				</fieldset>
			{/each}

			<fieldset class="flex items-center gap-2">
				<legend class="mb-1 font-medium">{m.mymap_sac()}</legend>
				{#each [0, 1] as end (end)}
					<select
						class="rounded-md border border-stone-300 px-2 py-1"
						aria-label="{m.mymap_sac()} {end === 0 ? m.mymap_from() : m.mymap_to()}"
						value={filters.sac[end]}
						onchange={(e) => {
							const next = [...filters.sac] as [number, number];
							next[end] = Number(e.currentTarget.value);
							filters.sac = next;
						}}
					>
						<option value={0}>{end === 0 ? m.mymap_from() : m.mymap_to()}</option>
						{#each [1, 2, 3, 4, 5, 6] as g (g)}
							<option value={g}>T{g}</option>
						{/each}
					</select>
					{#if end === 0}<span>–</span>{/if}
				{/each}
			</fieldset>

			{#if filters.kinds.length === 0 || filters.kinds.includes('journey')}
				<label class="flex items-start gap-2 text-xs text-stone-600">
					<input type="checkbox" bind:checked={filters.longest} />
					{m.mymap_longest()}
				</label>
			{/if}
			<label class="flex items-center gap-2">
				<input type="checkbox" bind:checked={filters.shared} />
				{m.mymap_shared()}
			</label>
			<div class="flex items-center justify-between gap-2">
				<label class="flex items-center gap-2">
					{m.mymap_color()}
					<select class="rounded-md border border-stone-300 px-2 py-1" bind:value={filters.color}>
						<option value="kind">{m.mymap_color_kind()}</option>
						<option value="sac">{m.mymap_color_sac()}</option>
					</select>
				</label>
				<button type="button" class="text-xs text-stone-600 underline" onclick={reset}
					>{m.mymap_reset()}</button
				>
			</div>
		</div>

		{#if failed}
			<p role="alert" class="text-sm text-red-700">{m.discover_failed()}</p>
		{:else if !loading && items.length === 0}
			<p class="text-sm text-stone-600">{m.mymap_empty()}</p>
		{/if}

		<ol class="flex flex-col gap-2" data-testid="mymap-results" aria-busy={loading}>
			{#each items as it, i (it.id)}
				<li
					class="rounded-md border border-stone-200 p-2 text-sm"
					data-testid="mymap-item"
					onmouseenter={() => (highlight = it.id)}
					onmouseleave={() => (highlight = undefined)}
				>
					<div class="flex items-center gap-2">
						<span class="inline-block size-3 shrink-0 rounded-full" style:background={color(i)}
						></span>
						<a href={href(it)} class="flex-1 font-medium hover:underline">{it.title}</a>
						<span class="text-xs text-stone-500">{itemKind(it.kind as Kind)}</span>
					</div>
					<div class="mt-1 flex items-center gap-2 text-xs text-stone-600 tabular-nums">
						{#if it.owner_username !== user.username}
							<span>{m.shared_by({ user: it.owner_username })}</span>
						{/if}
						<span class="ml-auto"
							>{formatDistance(it.distance_m)} · {formatDuration(it.duration_s, pace)} · ↑ {Math.round(
								it.ascent_m
							)} m</span
						>
						{#if it.sac_grade > 0}
							<span
								class="rounded px-1 font-semibold text-white"
								style:background={SAC_COLOR[`T${it.sac_grade}`] ?? '#a8a29e'}
								>{formatSAC(it.sac_grade, it.sac_max)}</span
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
					<div class="mt-1"><TagChips tags={it.tags} /></div>
				</li>
			{/each}
		</ol>

		{#if more}
			<p class="text-xs text-stone-500" data-testid="mymap-more">{m.discover_more()}</p>
		{/if}
	</aside>
</main>
