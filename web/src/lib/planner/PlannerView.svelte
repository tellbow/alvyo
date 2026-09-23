<script lang="ts">
	import type { Map as MapLibreMap, MapMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { resolve } from '$app/paths';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import type { Journey, Me, Route } from '$lib/api/client';
	import StageSavePanel from '$lib/journeys/StageSavePanel.svelte';
	import SharePanel from '$lib/sharing/SharePanel.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import SavePanel from './SavePanel.svelte';
	import StatsPanel from './StatsPanel.svelte';
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

	function onready(m: MapLibreMap, l: typeof MapLibre) {
		map = m;
		lib = l;
		m.on('click', (e: MapMouseEvent) => {
			if (!user) return;
			const hit = m.queryRenderedFeatures(e.point, {
				layers: ROUTE_LINES.filter((id) => m.getLayer(id))
			})[0];
			if (hit) planner.insert(Number(hit.properties.leg) + 1, e.lngLat.lng, e.lngLat.lat);
			else planner.add(e.lngLat.lng, e.lngLat.lat);
		});
		m.doubleClickZoom.disable(); // double-click removes anchors
	}

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
			<RouteLayers {map} {lib} {planner} {hover} {ghosts} />
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

				<section>
					<h3 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">
						{m.plan_legs()}
					</h3>
					<ol class="flex flex-col gap-2 text-sm">
						{#each planner.legs as slot, i (slot.key)}
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
									<p class="mt-1 text-xs text-red-700" role="alert">{legError(slot)}</p>
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
</style>
