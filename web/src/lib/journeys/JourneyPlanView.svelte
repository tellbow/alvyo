<script lang="ts">
	import type { Map as MapLibreMap, MapMouseEvent, Marker } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api, type FoundPlace, type Me, type Proposal, type Suggestion } from '$lib/api/client';
	import CollectionLayers from '$lib/collections/CollectionLayers.svelte';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { SAC_COLOR } from '$lib/planner/colors';
	import PlaceSearch from '$lib/planner/PlaceSearch.svelte';
	import { formatDistance, formatDuration, formatSAC } from '$lib/planner/route';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { stageColor } from './colors';
	import { single, stagesOf, switches, switchTo, whole, type Picked } from './suggestions';

	let { user }: { user: Me } = $props();
	const pace = $derived(user.speed_factor ?? 1);
	const hydrated = new Hydrated();

	type Point = { lon: number; lat: number; name?: string };
	type Kind = 'hut' | 'hotel' | 'campsite' | 'pt_stop';
	const KINDS: { kind: Kind; label: () => string }[] = [
		{ kind: 'hut', label: m.jplan_kind_hut },
		{ kind: 'hotel', label: m.jplan_kind_hotel },
		{ kind: 'campsite', label: m.jplan_kind_campsite },
		{ kind: 'pt_stop', label: m.jplan_kind_pt_stop }
	];

	// Start, points to pass, destination: each new point is the destination.
	let points = $state<Point[]>([]);
	let by = $state<'days' | 'hours'>('days');
	let days = $state(3);
	// Hours per day, from … to: as few days as fit.
	let minHours = $state(4);
	let maxPerDay = $state(8);
	let maxHours = $state('');
	const asksOk = $derived(by === 'days' || (minHours > 0 && minHours <= maxPerDay));
	let profile = $state<'hike' | 'alpine'>('hike');
	let kinds = $state<Kind[]>(['hut', 'hotel']);
	let proposal = $state<Proposal>();
	// Suggested ways, and the days of the journey put together from them.
	let ways = $state<Suggestion[]>([]);
	let picked = $state<Picked[]>([]);
	const chosen = $derived(single(ways, picked));
	const mixed = $derived(ways.length > 0 && chosen === undefined);
	let busy = $state(false);
	let problem = $state('');
	let title = $state('');

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib = $state<typeof MapLibre>();
	let highlight = $state<string>();

	const stageLines = $derived(
		(proposal?.stages ?? []).map((st, i) => ({
			id: String(i),
			lines: [st.legs.flatMap((l) => l.coordinates.map((c) => [c[0], c[1]] as [number, number]))]
		}))
	);
	// The ways not taken, grey below the days.
	const others = $derived(
		ways.flatMap((w, k) =>
			k === chosen
				? []
				: [
						{
							id: `way-${k}`,
							lines: w.proposal.stages.map((st) =>
								st.legs.flatMap((l) => l.coordinates.map((c) => [c[0], c[1]] as [number, number]))
							)
						}
					]
		)
	);
	const lineColor = (i: number) => (i < others.length ? '#a8a29e' : stageColor(i - others.length));
	const total = $derived(
		(proposal?.stages ?? []).reduce((sum, st) => sum + st.totals.distance_m, 0)
	);

	function onready(mp: MapLibreMap, l: typeof MapLibre) {
		map = mp;
		lib = l;
		mp.on('click', (e: MapMouseEvent) => {
			// A click on a hut opens its popup instead.
			if (e.defaultPrevented || e.originalEvent.target !== mp.getCanvas()) return;
			addPoint({ lon: e.lngLat.lng, lat: e.lngLat.lat });
		});
	}

	function center(): [number, number] | undefined {
		const c = map?.getCenter();
		return c ? [c.lng, c.lat] : undefined;
	}

	function reset() {
		proposal = undefined;
		ways = [];
		picked = [];
	}

	function addPoint(p: Point) {
		points = [...points, p];
		reset();
		if (!title && points.length >= 2 && points[0].name && p.name) {
			title = `${points[0].name} – ${p.name}`;
		}
	}

	function addPlace(p: FoundPlace) {
		addPoint({ lon: p.at[0], lat: p.at[1], name: p.name });
		map?.flyTo({ center: [p.at[0], p.at[1]], zoom: Math.max(map.getZoom(), 11) });
	}

	function removePoint(i: number) {
		points = points.filter((_, k) => k !== i);
		reset();
	}

	// Point markers, drawn anew when the points change.
	$effect(() => {
		if (!map || !lib) return;
		const placed: Marker[] = points.map((p, i) => {
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			const dot = el.firstElementChild as HTMLElement;
			const kind = i === 0 ? 'start' : i === points.length - 1 ? 'end' : 'via';
			dot.className = `plan-point plan-point-${kind}`;
			dot.textContent = kind === 'via' ? String(i) : '';
			dot.dataset.testid = 'plan-point';
			return new lib!.Marker({ element: el }).setLngLat([p.lon, p.lat]).addTo(map!);
		});
		return () => placed.forEach((mk) => mk.remove());
	});

	function request() {
		// Hours are shown at the hiker's pace; the API counts Swiss hiking time.
		const swiss = (h: number) => h / pace;
		const max = Number(maxHours);
		return {
			points: points.map((p) => ({ lon: p.lon, lat: p.lat })),
			profile,
			...(by === 'days'
				? { days, ...(max > 0 ? { max_hours: swiss(max) } : {}) }
				: { min_hours: swiss(minHours), max_hours: swiss(maxPerDay) }),
			kinds
		};
	}

	async function plan(ends?: string[]) {
		busy = true;
		problem = '';
		// Moving a night of a suggested way plans along that way.
		const way = ends ? chosen : undefined;
		const asked = points;
		const { data, response } = await api().POST('/journeys/plan', {
			body: {
				...request(),
				...(way !== undefined ? { points: ways[way].points } : {}),
				...(ends ? { ends } : {})
			}
		});
		busy = false;
		if (points !== asked) return; // points added or removed meanwhile: plan again
		if (!data) {
			problem = response.status === 422 ? m.jplan_no_path() : m.jplan_failed();
			return;
		}
		if (way !== undefined) {
			ways[way] = { ...ways[way], proposal: data as Proposal };
			picked = whole(ways, way);
		} else {
			ways = [];
			picked = [];
		}
		proposal = data as Proposal;
		fit();
	}

	async function suggest() {
		busy = true;
		problem = '';
		const asked = points;
		const { data, response } = await api().POST('/journeys/suggest', { body: request() });
		busy = false;
		if (points !== asked) return;
		if (!data) {
			problem = response.status === 422 ? m.jplan_no_path() : m.jplan_failed();
			return;
		}
		ways = data.suggestions as Suggestion[];
		choose(0);
	}

	function choose(k: number) {
		picked = whole(ways, k);
		proposal = { ...ways[k].proposal, stages: stagesOf(ways, picked) };
		fit();
	}

	/** Goes on after day i along another way that sleeps at the same place. */
	function goOn(i: number, to: Picked) {
		if (!proposal) return;
		picked = switchTo(ways, picked, i, to);
		proposal = { ...proposal, stages: stagesOf(ways, picked) };
	}

	function wayName(k: number) {
		const via = ways[k].via;
		return via ? m.jplan_way_via({ n: k + 1, place: via }) : m.jplan_way_direct({ n: k + 1 });
	}

	function nights(w: Suggestion) {
		return w.proposal.stages.flatMap((st) => (st.end_place ? [st.end_place.name] : [])).join(' · ');
	}

	function fit() {
		const pts = stageLines.flatMap((s) => s.lines[0]);
		if (!map || !lib || pts.length === 0) return;
		const b = pts.reduce((acc, c) => acc.extend(c), new lib.LngLatBounds(pts[0], pts[0]));
		map.fitBounds(b, { padding: 60, duration: 0 });
	}

	/** Ends day i at another place; the others stay where they are. */
	function endAt(i: number, placeId: string) {
		if (!proposal) return;
		const ends = proposal.stages.slice(0, -1).map((st) => st.end_place!.id);
		ends[i] = placeId;
		void plan(ends);
	}

	async function create(e: SubmitEvent) {
		e.preventDefault();
		if (!proposal) return;
		busy = true;
		const { data } = await api().POST('/journeys', {
			body: {
				title: title.trim(),
				visibility: 'private',
				stages: proposal.stages.map((st) => ({
					profile: st.profile as 'hike' | 'alpine',
					anchors: st.anchors,
					legs: st.legs,
					accommodation: st.accommodation,
					...(st.start_place ? { start_place_id: st.start_place.id } : {}),
					...(st.end_place ? { end_place_id: st.end_place.id } : {})
				}))
			}
		});
		busy = false;
		if (data) await goto(resolve('/journeys/[id]', { id: data.id }));
		else problem = m.error_generic();
	}

	function onsubmit(e: SubmitEvent) {
		e.preventDefault();
		void plan();
	}
</script>

<Seo title={m.jplan_title()} index={false} />

<main class="flex min-h-0 flex-1">
	<section class="relative flex-1">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map}
			<CollectionLayers
				{map}
				items={[...others, ...stageLines]}
				color={lineColor}
				{highlight}
				onclick={(id) => (id.startsWith('way-') ? choose(Number(id.slice(4))) : (highlight = id))}
			/>
		{/if}
	</section>

	<aside
		class="flex w-96 flex-col gap-4 overflow-y-auto border-l border-stone-200 bg-surface p-4"
		data-testid="journey-plan-panel"
	>
		<div>
			<h1 class="text-xl font-semibold">{m.jplan_title()}</h1>
			<p class="mt-1 text-sm text-stone-600">{m.jplan_intro()}</p>
		</div>

		<section>
			{#if points.length > 0}
				<ol class="mb-2 flex flex-col gap-1 text-sm" data-testid="plan-points">
					{#each points as p, i (i)}
						<li class="flex items-center gap-2">
							<span
								class="plan-point shrink-0 plan-point-{i === 0
									? 'start'
									: i === points.length - 1
										? 'end'
										: 'via'}">{i > 0 && i < points.length - 1 ? i : ''}</span
							>
							<span class="min-w-0 flex-1 truncate" class:text-stone-500={!p.name}
								>{p.name ?? m.plan_point_map()}</span
							>
							<button
								type="button"
								class="w-6 rounded text-stone-600 hover:bg-stone-100"
								aria-label={m.plan_point_remove()}
								title={m.plan_point_remove()}
								onclick={() => removePoint(i)}>×</button
							>
						</li>
					{/each}
				</ol>
			{/if}
			<PlaceSearch
				label={points.length === 0
					? m.plan_search_start()
					: points.length === 1
						? m.plan_search_end()
						: m.plan_search_more()}
				near={center}
				onpick={addPlace}
			/>
		</section>

		<form method="post" {onsubmit} class="flex flex-col gap-3 text-sm">
			<fieldset class="flex flex-col gap-1">
				<legend class="mb-1 font-medium">{m.jplan_by()}</legend>
				<label class="flex items-center gap-2">
					<input type="radio" bind:group={by} value="days" />
					{m.jplan_by_days()}
					<input
						type="number"
						min="1"
						max="60"
						class="w-16 rounded-md border border-stone-300 px-2 py-1"
						aria-label={m.jplan_days()}
						bind:value={days}
						onfocus={() => (by = 'days')}
					/>
				</label>
				<div class="flex items-center gap-2">
					<label class="flex items-center gap-2">
						<input type="radio" bind:group={by} value="hours" />
						{m.jplan_by_hours()}
					</label>
					<input
						type="number"
						min="1"
						max="16"
						step="0.5"
						class="w-16 rounded-md border border-stone-300 px-2 py-1"
						aria-label={m.jplan_hours_min()}
						bind:value={minHours}
						onfocus={() => (by = 'hours')}
					/>
					–
					<input
						type="number"
						min="1"
						max="16"
						step="0.5"
						class="w-16 rounded-md border border-stone-300 px-2 py-1"
						aria-label={m.jplan_hours_max()}
						bind:value={maxPerDay}
						onfocus={() => (by = 'hours')}
					/>
				</div>
				{#if by === 'days'}
					<label class="flex items-center gap-2">
						<span class="text-stone-600">{m.jplan_max()}</span>
						<input
							type="number"
							min="1"
							max="20"
							step="0.5"
							class="w-16 rounded-md border border-stone-300 px-2 py-1"
							bind:value={maxHours}
						/>
					</label>
				{/if}
			</fieldset>

			<fieldset>
				<legend class="mb-1 font-medium">{m.jplan_kinds()}</legend>
				<div class="flex flex-col gap-1">
					{#each KINDS as k (k.kind)}
						<label class="flex items-center gap-2">
							<input type="checkbox" bind:group={kinds} value={k.kind} />
							{k.label()}
						</label>
					{/each}
				</div>
			</fieldset>

			<label class="flex flex-col gap-1">
				<span class="font-medium">{m.plan_profile()}</span>
				<select bind:value={profile} class="rounded-md border border-stone-300 px-2 py-1.5">
					<option value="hike">{m.plan_profile_hike()}</option>
					<option value="alpine">{m.plan_profile_alpine()}</option>
				</select>
			</label>

			<button
				disabled={!hydrated.value || busy || points.length < 2 || !asksOk}
				class="rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover disabled:opacity-50"
			>
				{busy ? m.jplan_running() : m.jplan_submit()}
			</button>
			<button
				type="button"
				disabled={!hydrated.value || busy || points.length < 2 || !asksOk}
				class="rounded-md border border-stone-300 px-3 py-1.5 hover:bg-stone-100 disabled:opacity-50"
				onclick={suggest}
			>
				{m.jplan_suggest()}
			</button>
		</form>

		{#if problem}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{problem}</p>{/if}

		{#if ways.length > 0}
			<section class="flex flex-col gap-2 text-sm" data-testid="plan-ways">
				<h2 class="font-medium">{m.jplan_ways()}</h2>
				{#each ways as w, k (k)}
					<button
						type="button"
						class="rounded-md border p-2 text-left {chosen === k
							? 'border-stone-500'
							: 'border-stone-200 hover:bg-stone-100'}"
						aria-pressed={chosen === k}
						data-testid="plan-way"
						onclick={() => choose(k)}
					>
						<span class="font-medium">{wayName(k)}</span>
						<span class="text-xs text-stone-600 tabular-nums">
							· {m.jplan_summary({
								days: w.proposal.stages.length,
								distance: formatDistance(
									w.proposal.stages.reduce((sum, st) => sum + st.totals.distance_m, 0)
								)
							})}
						</span>
						<span class="mt-0.5 block text-xs text-stone-600">{nights(w)}</span>
					</button>
				{/each}
				{#if ways.length > 1}
					<p class="text-xs text-stone-600">{m.jplan_ways_hint()}</p>
				{/if}
			</section>
		{/if}

		{#if proposal}
			<p class="text-sm font-medium" data-testid="plan-summary">
				{m.jplan_summary({ days: proposal.stages.length, distance: formatDistance(total) })}
			</p>
			<ol class="flex flex-col gap-2" data-testid="plan-stages">
				{#each proposal.stages as st, i (i)}
					<li
						class="rounded-md border p-2 text-sm {highlight === String(i)
							? 'border-stone-500'
							: 'border-stone-200'}"
						data-testid="plan-stage"
						onmouseenter={() => (highlight = String(i))}
						onmouseleave={() => (highlight = undefined)}
					>
						<div class="flex items-center gap-2">
							<span class="inline-block size-3 rounded-full" style:background={stageColor(i)}
							></span>
							<span class="font-medium">{m.jplan_day({ n: i + 1 })}</span>
							<span class="ml-auto text-xs text-stone-600 tabular-nums">
								{formatDistance(st.totals.distance_m)} · {formatDuration(
									st.totals.duration_s,
									pace
								)}
								· ↑ {Math.round(st.totals.ascent_m)} m
							</span>
							{#if st.totals.sac_grade > 0}
								<span
									class="rounded px-1 text-xs font-semibold text-white"
									style:background={SAC_COLOR[`T${st.totals.sac_grade}`] ?? '#a8a29e'}
									>{formatSAC(st.totals.sac_grade, st.totals.sac_max)}</span
								>
							{/if}
						</div>
						<p class="mt-1" data-testid="plan-stage-end">
							→ {st.end_place ? st.end_place.name : m.jplan_to_end()}
							{#if mixed}
								<span class="text-xs text-stone-600">· {m.jplan_way({ n: picked[i].way + 1 })}</span
								>
							{/if}
							{#if st.end_place?.website}
								<!-- The hut's own website: resolve() does not apply. -->
								<!-- eslint-disable svelte/no-navigation-without-resolve -->
								·
								<a
									href={st.end_place.website}
									target="_blank"
									rel="noopener noreferrer nofollow"
									class="text-accent-ink underline">{m.jplan_website()} ↗</a
								>
								<!-- eslint-enable svelte/no-navigation-without-resolve -->
							{/if}
						</p>
						{#if st.end_place?.kind === 'hut'}
							<p class="mt-1 text-xs text-amber-800 dark:text-amber-200">{m.jplan_hut_hint()}</p>
						{/if}
						{#if st.over_max}
							<p class="mt-1 text-xs text-amber-800 dark:text-amber-200">{m.jplan_over_max()}</p>
						{:else if st.under_min}
							<p class="mt-1 text-xs text-amber-800 dark:text-amber-200">{m.jplan_under_min()}</p>
						{/if}
						{#if !mixed && (st.earlier || st.later)}
							<div class="mt-1 flex flex-wrap gap-2 text-xs">
								{#if st.earlier}
									<button
										type="button"
										class="underline"
										disabled={busy}
										onclick={() => endAt(i, st.earlier!.id)}
										>{m.jplan_earlier({ place: st.earlier.name })}</button
									>
								{/if}
								{#if st.later}
									<button
										type="button"
										class="underline"
										disabled={busy}
										onclick={() => endAt(i, st.later!.id)}
										>{m.jplan_later({ place: st.later.name })}</button
									>
								{/if}
							</div>
						{/if}
						{#if ways.length > 1}
							{#each switches(ways, picked, i) as to (to.way)}
								<button
									type="button"
									class="mt-1 block text-xs text-accent-ink underline"
									data-testid="plan-switch"
									onclick={() => goOn(i, to)}>{m.jplan_switch({ n: to.way + 1 })}</button
								>
							{/each}
						{/if}
					</li>
				{/each}
			</ol>

			<form method="post" onsubmit={create} class="flex flex-col gap-2 text-sm">
				<label class="flex flex-col gap-1">
					<span class="font-medium">{m.field_title()}</span>
					<input
						bind:value={title}
						required
						maxlength="120"
						class="rounded-md border border-stone-300 px-2 py-1.5"
					/>
				</label>
				<button
					disabled={!hydrated.value || busy || !title.trim()}
					class="rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover disabled:opacity-50"
				>
					{m.jplan_create()}
				</button>
			</form>
		{/if}
	</aside>
</main>

<style>
	:global(.plan-point) {
		display: inline-block;
		width: 18px;
		height: 18px;
		border-radius: 9999px;
		border: 3px solid #a21caf;
		background: #fff;
		box-shadow: 0 1px 3px rgb(0 0 0 / 0.4);
		font:
			600 10px/12px system-ui,
			sans-serif;
		color: #581c87;
		text-align: center;
	}
	:global(.plan-point-start) {
		background: #16a34a;
		border-color: #fff;
	}
	:global(.plan-point-end) {
		background: #a21caf;
		border-color: #fff;
	}
</style>
