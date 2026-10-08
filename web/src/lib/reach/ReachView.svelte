<script lang="ts">
	import { intlLocale } from '$lib/util/locale';
	import { page } from '$app/state';
	import { choose } from '$lib/util/choose';
	import type { GeoJSONSource, Map as MapLibreMap, MapMouseEvent } from 'maplibre-gl';
	import { resolve } from '$app/paths';
	import { api, type FoundPlace, type Me } from '$lib/api/client';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import { ROUTE_PREFIX, type BaseMapId, type OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import PlaceSearch from '$lib/planner/PlaceSearch.svelte';
	import PlanTabs from '$lib/planner/PlanTabs.svelte';
	import type { Profile } from '$lib/planner/route';
	import Seo from '$lib/seo/Seo.svelte';

	// «Wie weit komme ich?»: from a point on the map or a place, the areas
	// reached on foot within 2, 4 and 8 hours at the user's pace.
	let { user }: { user: Me | null } = $props();

	const COLORS: Record<number, string> = { 2: '#16a34a', 4: '#eab308', 8: '#dc2626' };
	const AREAS = ROUTE_PREFIX + 'reach';
	const START = ROUTE_PREFIX + 'reach-start';

	type Area = { hours: number; outline: number[][][] };

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let profile = $state<Profile>('hike');
	let start = $state<{ at: [number, number]; name: string }>();
	let areas = $state<Area[]>([]);
	let status = $state<'idle' | 'busy' | 'done' | 'error'>('idle');
	let error = $state('');
	let asked = 0;

	async function reach() {
		if (!start) return;
		const mine = ++asked;
		status = 'busy';
		const { data, response } = await api().POST('/routing/reach', {
			body: { from: { lon: start.at[0], lat: start.at[1] }, profile }
		});
		if (mine !== asked) return;
		if (data) {
			areas = data.areas;
			status = 'done';
			return;
		}
		areas = [];
		status = 'error';
		error =
			response.status === 422
				? m.reach_error_422()
				: response.status === 429
					? m.leg_error_429()
					: m.reach_error_other();
	}

	function startAt(at: [number, number], name = '') {
		start = { at, name };
		void reach();
	}

	function pick(place: FoundPlace) {
		startAt([place.at[0], place.at[1]], place.name);
		map?.easeTo({ center: [place.at[0], place.at[1]], zoom: Math.min(map.getZoom(), 10) });
	}

	function center(): [number, number] | undefined {
		const c = map?.getCenter();
		return c ? [c.lng, c.lat] : undefined;
	}

	function onready(mp: MapLibreMap) {
		mp.addSource(AREAS, { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
		mp.addLayer({
			id: AREAS,
			type: 'fill',
			source: AREAS,
			paint: { 'fill-color': ['get', 'color'], 'fill-opacity': 0.35 }
		});
		// A white edge under the outline: the trails are yellow and red too.
		mp.addLayer({
			id: AREAS + '-edge',
			type: 'line',
			source: AREAS,
			paint: { 'line-color': '#ffffff', 'line-width': 5 }
		});
		mp.addLayer({
			id: AREAS + '-line',
			type: 'line',
			source: AREAS,
			paint: { 'line-color': ['get', 'color'], 'line-width': 2.5 }
		});
		mp.addSource(START, { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
		mp.addLayer({
			id: START,
			type: 'circle',
			source: START,
			paint: {
				'circle-radius': 7,
				'circle-color': '#1c1917',
				'circle-stroke-color': '#ffffff',
				'circle-stroke-width': 2
			}
		});
		mp.on('click', (e: MapMouseEvent) => {
			// Clicks on a hut's or a stop's pin are their own.
			if (!user || e.defaultPrevented || e.originalEvent.target !== mp.getCanvas()) return;
			startAt([e.lngLat.lng, e.lngLat.lat]);
		});
		map = mp;
	}

	// The areas, the largest underneath; the start on top.
	$effect(() => {
		if (!map) return;
		(map.getSource(AREAS) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: [...areas]
				.sort((a, b) => b.hours - a.hours)
				.map((a) => ({
					type: 'Feature',
					geometry: { type: 'Polygon', coordinates: a.outline },
					properties: { hours: a.hours, color: COLORS[a.hours] ?? '#78716c' }
				}))
		});
		(map.getSource(START) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: start
				? [{ type: 'Feature', geometry: { type: 'Point', coordinates: start.at }, properties: {} }]
				: []
		});
	});
	// Back here after logging in.
	const loginHref = $derived(
		`${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname + page.url.search)}`
	);
</script>

<Seo title={m.reach_title()} index={false} />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if status === 'busy'}
			<p
				class="pointer-events-none absolute inset-x-0 top-14 z-10 mx-auto w-fit max-w-[calc(100%-2rem)] rounded-md bg-stone-900/85 px-3 py-2 text-sm text-white shadow"
				role="status"
			>
				{m.reach_busy()}
			</p>
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-80 md:flex-none md:border-t-0 md:border-l"
		data-testid="reach-panel"
	>
		<PlanTabs current="reach" />
		<h1 class="text-lg font-semibold">{m.reach_title()}</h1>
		{#if !user}
			<p class="rounded-md bg-stone-100 p-3 text-sm">
				{m.reach_hint_login()}
				<!-- resolve() gives the path; only the query is added -->
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
				<a href={loginHref} class="text-accent-ink underline">{m.nav_login()}</a>
			</p>
		{:else}
			<p class="text-sm text-stone-600">{m.reach_intro()}</p>
			<PlaceSearch label={m.reach_search()} near={center} onpick={pick} />
			<label class="flex flex-col gap-1 text-sm">
				<span class="font-medium">{m.plan_profile()}</span>
				<select
					class="rounded-md border border-stone-300 px-2 py-1.5"
					bind:value={profile}
					use:choose={() => void reach()}
					data-testid="reach-profile"
				>
					<option value="hike">{m.plan_profile_hike()}</option>
					<option value="alpine">{m.plan_profile_alpine()}</option>
				</select>
			</label>
			{#if start}
				<p class="text-sm" data-testid="reach-start">
					<span class="font-medium">{m.reach_start()}:</span>
					{start.name || `${start.at[1].toFixed(4)}, ${start.at[0].toFixed(4)}`}
				</p>
			{/if}
			{#if status === 'error'}
				<p class="text-sm text-red-700 dark:text-red-400" role="alert">{error}</p>
			{:else if status === 'done'}
				<ul class="flex flex-col gap-1 text-sm" data-testid="reach-legend">
					{#each areas as a (a.hours)}
						<li class="flex items-center gap-2">
							<span
								class="inline-block size-3 rounded-sm"
								style:background-color={COLORS[a.hours]}
								aria-hidden="true"
							></span>
							{m.reach_within({ hours: a.hours })}
						</li>
					{/each}
				</ul>
				<p class="text-xs text-stone-500">{m.reach_note()}</p>
				{#if (user.speed_factor ?? 1) !== 1}
					<p class="text-xs text-stone-500">
						{m.reach_pace({ pace: (user.speed_factor ?? 1).toLocaleString(intlLocale()) })}
						<a href={resolve('/account')} class="text-accent-ink underline"
							>{m.reach_pace_change()}</a
						>
					</p>
				{/if}
			{/if}
		{/if}
	</aside>
</main>
