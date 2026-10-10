<script lang="ts">
	import { page } from '$app/state';
	import { choose } from '#lib/util/choose.js';
	import PlanTabs from './PlanTabs.svelte';
	import type { Map as MapLibreMap, MapMouseEvent } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import {
		api,
		type FoundPlace,
		type Journey,
		type Me,
		type Notice,
		type ProtectedArea,
		type Route
	} from '#lib/api/client.js';
	import StageSavePanel from '#lib/journeys/StageSavePanel.svelte';
	import SharePanel from '#lib/sharing/SharePanel.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import ProfileDock from './ProfileDock.svelte';
	import PlaceSearch from './PlaceSearch.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import SavePanel from './SavePanel.svelte';
	import StatsPanel from './StatsPanel.svelte';
	import ProtectedAreas from '#lib/areas/ProtectedAreas.svelte';
	import Notices from '#lib/areas/Notices.svelte';
	import { fetchLeg } from './api';
	import { Planner, type LegSlot } from './planner.svelte';
	import { readPlanQuery } from './query';
	import { formatDistance, formatDuration, formatHeight, type Profile } from './route';

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
	const DRAG_KEY = 'alvyo.dragPath';
	let dragPath = $state(false);

	function setDragPath(on: boolean) {
		dragPath = on;
		try {
			localStorage.setItem(DRAG_KEY, on ? '1' : '');
		} catch {
			// storage blocked: the choice lasts for this page
		}
	}

	// A message over the map for a few seconds, e.g. that there is no other way.
	let notice = $state('');
	let noticeTimer: ReturnType<typeof setTimeout> | undefined;
	function notify(text: string) {
		notice = text;
		clearTimeout(noticeTimer);
		noticeTimer = setTimeout(() => (notice = ''), 5000);
	}
	const dragHint = () => notify(m.plan_drag_click());

	const planner = new Planner(fetchLeg);
	// svelte-ignore state_referenced_locally
	if (route)
		planner.load({ profile: route.profile as Profile, anchors: route.anchors, legs: route.legs });
	// A new route from start to destination in the address (from «Reichweite»).
	// svelte-ignore state_referenced_locally
	const fromQuery = !route && !stage ? readPlanQuery(page.url.searchParams) : undefined;
	if (fromQuery) planner.load({ ...fromQuery, legs: [] });

	// Leaving unsaved points asks first; closing the tab gets the browser's
	// own question (cancel on «leave»).
	beforeNavigate(({ cancel, willUnload }) => {
		if (!planner.dirty || planner.anchors.length === 0) return;
		if (willUnload || !confirm(m.plan_leave_unsaved())) cancel();
	});

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

	// Announced when the route is computing and when it is done.
	const routeStatus = $derived(
		planner.legs.length === 0
			? ''
			: planner.complete
				? m.plan_computed({
						distance: formatDistance(planner.totals.distanceM),
						time: formatDuration(planner.totals.durationS, pace)
					})
				: planner.legs.some((l) => l.state === 'loading')
					? m.plan_computing()
					: ''
	);

	const ROUTE_LINES = ['route-line', 'route-line-straight'];

	// The protected areas the planned line crosses, asked for once the line
	// has stopped changing for a moment.
	let areas = $state<ProtectedArea[]>();
	let notices = $state<Notice[]>();
	let areasFailed = $state(false);
	$effect(() => {
		const line = planner.complete ? planner.line.coordinates.map((c) => [c[0], c[1]]) : [];
		if (line.length < 2) {
			areas = undefined;
			notices = undefined;
			areasFailed = false;
			return;
		}
		let stale = false;
		const timer = setTimeout(async () => {
			const { data } = await api().POST('/routing/areas', {
				body: { line: line as [number, number][] }
			});
			if (stale) return;
			areas = data?.areas;
			notices = data?.notices;
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
			// Clicks on a point (a marker above the map) or a hut are their own.
			if (!user || e.defaultPrevented || e.originalEvent.target !== m.getCanvas()) return;
			const hit = m.queryRenderedFeatures(e.point, {
				layers: ROUTE_LINES.filter((id) => m.getLayer(id))
			})[0];
			if (!hit) planner.add(e.lngLat.lng, e.lngLat.lat);
			// Set to another way, a click adds no point: dragging moves the leg.
			else if (dragPath !== e.originalEvent.altKey) dragHint();
			else planner.insert(Number(hit.properties.leg) + 1, e.lngLat.lng, e.lngLat.lat);
		});
		m.doubleClickZoom.disable(); // double-click removes anchors
		// A saved route opens with the map on it, not where the map was last;
		// start and destination from the address too.
		const coords = route
			? planner.line.coordinates
			: fromQuery
				? planner.anchors.map((a) => [a.lon, a.lat])
				: [];
		if (coords.length > 0) {
			const bounds = coords.reduce(
				(b, c) => b.extend([c[0], c[1]]),
				new l.LngLatBounds([coords[0][0], coords[0][1]], [coords[0][0], coords[0][1]])
			);
			m.fitBounds(bounds, {
				padding: { top: 60, bottom: 200, left: 60, right: 60 },
				maxZoom: 16,
				duration: 0
			});
		}
	}

	function center(): [number, number] | undefined {
		const c = map?.getCenter();
		return c ? [c.lng, c.lat] : undefined;
	}

	/** A place found by search becomes the new last point; the map shows it. */
	function addPlace(p: Pick<FoundPlace, 'name' | 'at'>) {
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
	// Back here after logging in.
	const loginHref = $derived(
		`${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname + page.url.search)}`
	);
</script>

<Seo title={route?.title ?? m.nav_plan()} index={false} />

<svelte:window {onkeydown} />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map
			bind:base
			bind:overlays
			{onready}
			placeAction={user
				? { label: m.map_place_add(), run: (p) => addPlace({ name: p.name, at: [p.lon, p.lat] }) }
				: undefined}
		/>
		<LayerSwitcher bind:base bind:overlays />
		{#if map && lib}
			<RouteLayers {map} {lib} {planner} {hover} {ghosts} {dragPath} onnotice={notify} />
		{/if}
		<!-- Always there, so screen readers announce what is written into it. -->
		<p
			role="status"
			class={[
				'pointer-events-none absolute inset-x-0 top-14 z-10 mx-auto w-fit max-w-[calc(100%-2rem)] rounded-md bg-stone-900/85 px-3 py-2 text-sm text-white shadow',
				!notice && 'sr-only'
			]}
			data-testid={notice ? 'map-notice' : undefined}
		>
			{notice}
		</p>
		<p class="sr-only" aria-live="polite">{routeStatus}</p>
		{#if planner.line.coordinates.length > 1}
			<ProfileDock>
				<ElevationProfile line={planner.line} bind:hover={hoverIndex} />
			</ProfileDock>
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-80 md:flex-none md:border-t-0 md:border-l"
		data-testid="planner-panel"
	>
		<h1 class="sr-only">{route?.title ?? m.nav_plan()}</h1>
		<PlanTabs current="route" />
		{#if !user}
			<p class="rounded-md bg-stone-100 p-3 text-sm">
				{m.plan_hint_login()}
				<!-- resolve() gives the path; only the query is added -->
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
				<a href={loginHref} class="text-accent-ink underline">{m.nav_login()}</a>
			</p>
		{:else}
			<label class="flex flex-col gap-1 text-sm">
				<span class="font-medium">{m.plan_profile()}</span>
				<select
					class="rounded-md border border-stone-400 px-2 py-1.5"
					value={planner.profile}
					use:choose={(v) => planner.setProfile(v as Profile)}
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
				<h2 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">
					{m.plan_points()}
				</h2>
				{#if planner.anchors.length > 0}
					<ol class="mb-2 flex flex-col gap-1 text-sm">
						{#each planner.anchors as a, i (a.id)}
							{@const kind = i === 0 ? 'start' : i === planner.anchors.length - 1 ? 'end' : 'via'}
							{@const height = planner.height(i)}
							{@const point = a.name ?? m.plan_point_map()}
							<li class="flex items-center gap-1" data-testid="point">
								<span class="anchor anchor-{kind} shrink-0" style="cursor: default"
									>{kind === 'via' ? i : ''}<span class="sr-only"
										>{kind === 'start'
											? m.plan_point_start()
											: kind === 'end'
												? m.plan_point_end()
												: ''}</span
									></span
								>
								<span class="min-w-0 flex-1 truncate" class:text-stone-500={!a.name}
									>{a.name ?? m.plan_point_map()}</span
								>
								{#if height !== undefined}
									<span class="shrink-0 text-xs text-stone-500 tabular-nums"
										>{formatHeight(height)}</span
									>
								{/if}
								<button
									type="button"
									class="icon-button"
									aria-label={m.plan_point_action({ point, action: m.plan_point_up() })}
									title={m.plan_point_up()}
									disabled={i === 0}
									onclick={() => planner.reorder(i, i - 1)}>↑</button
								>
								<button
									type="button"
									class="icon-button"
									aria-label={m.plan_point_action({ point, action: m.plan_point_down() })}
									title={m.plan_point_down()}
									disabled={i === planner.anchors.length - 1}
									onclick={() => planner.reorder(i, i + 1)}>↓</button
								>
								<button
									type="button"
									class="icon-button"
									aria-label={m.plan_point_action({ point, action: m.plan_point_remove() })}
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
				<Notices {notices} />
				<ProtectedAreas {areas} failed={areasFailed} />

				<section>
					<h2 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">
						{m.plan_legs()}
					</h2>
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
										<span class="flex-1 text-stone-500">…</span>
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
								{#if slot.state === 'ok' && slot.leg.alpine && !planner.anchors[i + 1]?.alpine}
									<!-- «Wandern» goes round a harder part (as at Chamanna Jenatsch). -->
									<p class="mt-1 text-xs text-stone-600" data-testid="leg-alpine">
										{m.leg_alpine_shorter({
											alpine: formatDistance(slot.leg.alpine.distance_m),
											hike: formatDistance(slot.leg.distance_m)
										})}
										{#if slot.leg.alpine.sac_grade > 3}
											{m.leg_alpine_grade({ grade: `T${slot.leg.alpine.sac_grade}` })}
										{/if}
										<button
											type="button"
											class="ml-1 underline pointer-coarse:py-2"
											onclick={() => planner.setAlpine(i, true)}>{m.leg_alpine_use()}</button
										>
									</p>
								{:else if planner.anchors[i + 1]?.alpine && planner.profile === 'hike'}
									<p class="mt-1 text-xs text-stone-600" data-testid="leg-alpine-used">
										{m.leg_alpine_used()}
										<button
											type="button"
											class="ml-1 underline"
											onclick={() => planner.setAlpine(i, false)}>{m.leg_alpine_undo()}</button
										>
									</p>
								{/if}
								{#if slot.state === 'error'}
									<p class="mt-1 text-xs text-red-700 dark:text-red-400" role="alert">
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
</style>
