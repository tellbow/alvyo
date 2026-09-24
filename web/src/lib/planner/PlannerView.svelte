<script lang="ts">
	import type { Map as MapLibreMap, MapMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { resolve } from '$app/paths';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import {
		api,
		type FoundPlace,
		type Journey,
		type Me,
		type ProtectedArea,
		type Route
	} from '$lib/api/client';
	import StageSavePanel from '$lib/journeys/StageSavePanel.svelte';
	import SharePanel from '$lib/sharing/SharePanel.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import PlaceSearch from './PlaceSearch.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import SavePanel from './SavePanel.svelte';
	import StatsPanel from './StatsPanel.svelte';
	import ProtectedAreas from '$lib/areas/ProtectedAreas.svelte';
	import { fetchLeg } from './api';
	import { Planner, type LegSlot } from './planner.svelte';
	import { formatDistance, formatDuration, type Profile } from './route';

	let {
		user,
		route,
		stage
	}: {
		user: Me | null;
		route?: Route;
		/** planning the route of a journey stage */
		stage?: { journey: Journey; index: number };
	} = $props();

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib = $state<typeof MapLibre>();
	let hoverIndex = $state<number>();
	// What dragging the line does; remembered in this browser.
	const DRAG_KEY = 'odysgeh.dragPath';
	let dragPath = $state(false);

	function setDragPath(on: boolean) {
		dragPath = on;
		try {
			localStorage.setItem(DRAG_KEY, on ? '1' : '');
		} catch {
			// storage blocked: the choice lasts for this page
		}
	}

	const planner = new Planner(fetchLeg);
	// svelte-ignore state_referenced_locally
	if (route)
		planner.load({ profile: route.profile as Profile, anchors: route.anchors, legs: route.legs });

	/** The routed stages before and after this one, for continuity. */
	// svelte-ignore state_referenced_locally
	const neighbours = stage ? stageNeighbours(stage.journey, stage.index) : {};
	// A new stage starts where the previous one ended.
	// svelte-ignore state_referenced_locally
	if (!route && neighbours.prev) planner.add(neighbours.prev.at[0], neighbours.prev.at[1]);
	const ghosts: { at: number[]; label: string }[] = [];
	if (neighbours.prev)
		ghosts.push({ at: neighbours.prev.at, label: m.stage_ghost_prev({ n: neighbours.prev.n }) });
	if (neighbours.next)
		ghosts.push({ at: neighbours.next.at, label: m.stage_ghost_next({ n: neighbours.next.n }) });

	function stageNeighbours(j: Journey, index: number) {
		const out: { prev?: { at: number[]; n: number }; next?: { at: number[]; n: number } } = {};
		for (let i = index - 1; i >= 0 && !out.prev; i--) {
			const r = j.stage_list[i].route;
			if (r) out.prev = { at: r.end, n: i + 1 };
		}
		for (let i = index + 1; i < j.stage_list.length && !out.next; i++) {
			const r = j.stage_list[i].route;
			if (r) out.next = { at: r.start, n: i + 1 };
		}
		return out;
	}
	const pace = $derived(user?.speed_factor ?? 1);
	const hover = $derived.by((): [number, number] | undefined => {
		const c = hoverIndex !== undefined ? planner.line.coordinates[hoverIndex] : undefined;
		return c ? [c[0], c[1]] : undefined;
	});

	const ROUTE_LINES = ['route-line', 'route-line-straight'];

	// The protected areas the planned line crosses, asked for once the line
	// has stopped changing for a moment.
	let areas = $state<ProtectedArea[]>();
	let areasFailed = $state(false);
	$effect(() => {
		const line = planner.complete ? planner.line.coordinates.map((c) => [c[0], c[1]]) : [];
		if (line.length < 2) {
			areas = undefined;
			return;
		}
		let stale = false;
		const timer = setTimeout(async () => {
			const { data } = await api().POST('/routing/areas', {
				body: { line: line as [number, number][] }
			});
			if (stale) return;
			areas = data?.areas;
			areasFailed = !data;
		}, 800);
		return () => {
			stale = true;
			clearTimeout(timer);
		};
	});

	function onready(m: MapLibreMap, l: typeof MapLibre) {
		map = m;
		lib = l;
		try {
			dragPath = localStorage.getItem(DRAG_KEY) === '1';
		} catch {
			// storage blocked: the default
		}
		m.on('click', (e: MapMouseEvent) => {
			// Clicks on a point (a marker above the map) are the point's own.
			if (!user || e.originalEvent.target !== m.getCanvas()) return;
			const hit = m.queryRenderedFeatures(e.point, {
				layers: ROUTE_LINES.filter((id) => m.getLayer(id))
			})[0];
			if (hit) planner.insert(Number(hit.properties.leg) + 1, e.lngLat.lng, e.lngLat.lat);
			else planner.add(e.lngLat.lng, e.lngLat.lat);
		});
		m.doubleClickZoom.disable(); // double-click removes anchors
	}

	function center(): [number, number] | undefined {
		const c = map?.getCenter();
		return c ? [c.lng, c.lat] : undefined;
	}

	/** A place found by search becomes the new last point; the map shows it. */
	function addPlace(p: FoundPlace) {
		planner.add(p.at[0], p.at[1], p.name);
		if (!map || !lib) return;
		const pts = planner.anchors;
		if (pts.length === 1) {
			map.flyTo({ center: [p.at[0], p.at[1]], zoom: Math.max(map.getZoom(), 13) });
			return;
		}
		const b = pts.reduce(
			(acc, a) => acc.extend([a.lon, a.lat]),
			new lib.LngLatBounds([pts[0].lon, pts[0].lat], [pts[0].lon, pts[0].lat])
		);
		map.fitBounds(b, { padding: 80, maxZoom: 15 });
	}

	const searchLabel = $derived(
		planner.anchors.length === 0
			? m.plan_search_start()
			: planner.anchors.length === 1
				? m.plan_search_end()
				: m.plan_search_more()
	);

	function onkeydown(e: KeyboardEvent) {
		if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== 'z') return;
		if ((e.target as HTMLElement).closest('input, textarea')) return;
		e.preventDefault();
		if (e.shiftKey) planner.redo();
		else planner.undo();
	}

	function legError(slot: LegSlot): string {
		if (slot.state !== 'error') return '';
		if (slot.status === 422) return m.leg_error_422();
		if (slot.status === 503) return m.leg_error_503();
		if (slot.status === 429) return m.leg_error_429();
		return m.leg_error_other();
	}
</script>

<svelte:window {onkeydown} />

<main class="flex min-h-0 flex-1">
	<section class="relative flex-1">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map && lib}
			<RouteLayers {map} {lib} {planner} {hover} {ghosts} {dragPath} />
		{/if}
		{#if planner.line.coordinates.length > 1}
			<div
				class="absolute right-12 bottom-8 left-2 z-10 rounded-md bg-white/95 px-2 py-1 shadow ring-1 ring-stone-300"
			>
				<ElevationProfile line={planner.line} bind:hover={hoverIndex} />
			</div>
		{/if}
	</section>

	<aside
		class="flex w-80 flex-col gap-4 overflow-y-auto border-l border-stone-200 bg-white p-4"
		data-testid="planner-panel"
	>
		{#if !user}
			<p class="rounded-md bg-stone-100 p-3 text-sm">
				{m.plan_hint_login()}
				<a href={resolve('/login')} class="text-emerald-800 underline">{m.nav_login()}</a>
			</p>
		{:else}
			<label class="flex flex-col gap-1 text-sm">
				<span class="font-medium">{m.plan_profile()}</span>
				<select
					class="rounded-md border border-stone-300 px-2 py-1.5"
					value={planner.profile}
					onchange={(e) => planner.setProfile(e.currentTarget.value as Profile)}
				>
					<option value="hike">{m.plan_profile_hike()}</option>
					<option value="alpine">{m.plan_profile_alpine()}</option>
				</select>
			</label>

			<fieldset class="flex flex-col gap-1 text-sm" data-testid="drag-mode">
				<legend class="mb-1 font-medium">{m.plan_drag()}</legend>
				<div class="flex gap-3">
					<label class="flex items-center gap-1">
						<input
							type="radio"
							name="drag-mode"
							checked={!dragPath}
							onchange={() => setDragPath(false)}
						/>
						{m.plan_drag_point()}
					</label>
					<label class="flex items-center gap-1">
						<input
							type="radio"
							name="drag-mode"
							checked={dragPath}
							onchange={() => setDragPath(true)}
						/>
						{m.plan_drag_path()}
					</label>
				</div>
				<p class="text-xs text-stone-500">{m.plan_drag_hint()}</p>
			</fieldset>

			<section data-testid="points">
				<h3 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">
					{m.plan_points()}
				</h3>
				{#if planner.anchors.length > 0}
					<ol class="mb-2 flex flex-col gap-1 text-sm">
						{#each planner.anchors as a, i (a.id)}
							{@const kind = i === 0 ? 'start' : i === planner.anchors.length - 1 ? 'end' : 'via'}
							<li class="flex items-center gap-2" data-testid="point">
								<span class="anchor anchor-{kind} shrink-0" style="cursor: default"
									>{kind === 'via' ? i : ''}</span
								>
								<span class="min-w-0 flex-1 truncate" class:text-stone-500={!a.name}
									>{a.name ?? m.plan_point_map()}</span
								>
								<button
									type="button"
									class="icon"
									aria-label={m.plan_point_up()}
									title={m.plan_point_up()}
									disabled={i === 0}
									onclick={() => planner.reorder(i, i - 1)}>↑</button
								>
								<button
									type="button"
									class="icon"
									aria-label={m.plan_point_down()}
									title={m.plan_point_down()}
									disabled={i === planner.anchors.length - 1}
									onclick={() => planner.reorder(i, i + 1)}>↓</button
								>
								<button
									type="button"
									class="icon"
									aria-label={m.plan_point_remove()}
									title={m.plan_point_remove()}
									onclick={() => planner.remove(a.id)}>×</button
								>
							</li>
						{/each}
					</ol>
				{/if}
				<PlaceSearch label={searchLabel} near={center} onpick={addPlace} />
				{#if planner.anchors.length > 1}
					<p class="mt-1 text-xs text-stone-500">{m.plan_points_hint()}</p>
				{/if}
			</section>

			<div class="flex flex-wrap gap-2 text-sm">
				<button type="button" class="btn" disabled={!planner.canUndo} onclick={() => planner.undo()}
					>{m.plan_undo()}</button
				>
				<button type="button" class="btn" disabled={!planner.canRedo} onclick={() => planner.redo()}
					>{m.plan_redo()}</button
				>
				<button
					type="button"
					class="btn"
					disabled={planner.anchors.length < 2}
					onclick={() => planner.reverse()}
				>
					{m.plan_reverse()}
				</button>
				<button
					type="button"
					class="btn"
					disabled={planner.anchors.length === 0}
					onclick={() => planner.clear()}
				>
					{m.plan_clear()}
				</button>
			</div>

			{#if stage}
				<StageSavePanel {planner} journey={stage.journey} index={stage.index} {route} />
			{:else if planner.anchors.length > 1}
				<SavePanel {planner} {user} {route} />
			{/if}
			{#if route && route.role === 'owner' && !route.journey_id}
				<SharePanel kind="routes" id={route.id} verified={user.email_verified} />
			{/if}

			{#if planner.anchors.length < 2}
				<p class="text-sm text-stone-600">{m.plan_hint_click()}</p>
			{:else}
				<StatsPanel totals={planner.totals} {pace} />
				<ProtectedAreas {areas} failed={areasFailed} />

				<section>
					<h3 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">
						{m.plan_legs()}
					</h3>
					<ol class="flex flex-col gap-2 text-sm">
						{#each planner.legs as slot, i (planner.anchors[i + 1]?.id ?? slot.key)}
							<li
								class="rounded-md border border-stone-200 p-2"
								data-testid="leg"
								data-state={slot.state}
							>
								<div class="flex items-center justify-between gap-2">
									<span class="font-medium">{i + 1}</span>
									{#if slot.state === 'ok'}
										<span class="flex-1 text-stone-600 tabular-nums">
											{formatDistance(slot.leg.distance_m)} · {formatDuration(
												slot.leg.duration_s,
												pace
											)}
										</span>
									{:else if slot.state === 'loading'}
										<span class="flex-1 text-stone-400">…</span>
									{:else}
										<span class="flex-1"></span>
									{/if}
									<label class="flex items-center gap-1 text-xs text-stone-600">
										<input
											type="checkbox"
											checked={planner.anchors[i + 1]?.straight}
											onchange={(e) => planner.setStraight(i, e.currentTarget.checked)}
										/>
										{m.plan_straight()}
									</label>
								</div>
								{#if slot.state === 'error'}
									<p class="mt-1 text-xs text-red-700" role="alert">
										{legError(slot)}
										{#if slot.status !== 422}
											<button
												type="button"
												class="ml-1 underline"
												data-testid="leg-retry"
												onclick={() => planner.retry()}>{m.leg_retry()}</button
											>
										{/if}
									</p>
								{/if}
							</li>
						{/each}
					</ol>
				</section>
			{/if}
		{/if}
	</aside>
</main>

<style>
	.btn {
		border-radius: 0.375rem;
		padding: 0.25rem 0.625rem;
		box-shadow: inset 0 0 0 1px var(--color-stone-300);
	}
	.btn:hover:not(:disabled) {
		background: var(--color-stone-100);
	}
	.btn:disabled {
		opacity: 0.4;
	}
	.icon {
		width: 1.5rem;
		border-radius: 0.25rem;
		color: var(--color-stone-600);
	}
	.icon:hover:not(:disabled) {
		background: var(--color-stone-100);
	}
	.icon:disabled {
		opacity: 0.3;
	}
</style>
