<script lang="ts">
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me, type Revision, type Route } from '$lib/api/client';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { hikeDate, savedAt } from '$lib/util/locale';
	import AddToCollection from '$lib/collections/AddToCollection.svelte';
	import { Community } from '$lib/community/community.svelte';
	import Social from '$lib/community/Social.svelte';
	import { Gallery } from '$lib/photos/gallery.svelte';
	import PhotoPins from '$lib/photos/PhotoPins.svelte';
	import Photos from '$lib/photos/Photos.svelte';
	import TagChips from '$lib/tags/TagChips.svelte';
	import { breakdownParts } from './breakdown';
	import Breakdowns from './Breakdowns.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import ProfileDock from './ProfileDock.svelte';
	import Revisions from './Revisions.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import StatsPanel from './StatsPanel.svelte';
	import ProtectedAreas from '$lib/areas/ProtectedAreas.svelte';
	import Notices from '$lib/areas/Notices.svelte';
	import Pois from '$lib/map/Pois.svelte';
	import PoiPins from '$lib/map/PoiPins.svelte';
	import type { Poi } from '$lib/map/places';
	import RouteWeather from '$lib/weather/RouteWeather.svelte';
	import OpenInApp from '$lib/sharing/OpenInApp.svelte';
	import Travel from '$lib/travel/Travel.svelte';
	import TravelLayers from '$lib/travel/TravelLayers.svelte';
	import { routeEnds } from '$lib/travel/travel';
	import type { Trip } from '$lib/api/client';
	import type { Notice, ProtectedArea } from '$lib/api/client';
	import { onMount } from 'svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { TRAIL_COLOR } from './colors';
	import { Planner } from './planner.svelte';
	import { formatDistance, formatHeight, formatDuration, formatSAC, type Profile } from './route';

	// With `revision`, `route` has the line it had then.
	let {
		route,
		token,
		user,
		revision
	}: { route: Route; token?: string; user: Me | null; revision?: Revision } = $props();

	let areas = $state<ProtectedArea[]>();
	let notices = $state<Notice[]>();
	let areasFailed = $state(false);
	onMount(async () => {
		const { data } = await api().GET('/routes/{id}/areas', {
			params: { path: { id: route.id }, query: token ? { t: token } : {} }
		});
		areas = data?.areas;
		notices = data?.notices;
		areasFailed = !data;
	});
	// Link previews (Signal, WhatsApp, Slack …) read these tags from the SSR page.
	const summary = $derived(
		[
			formatDistance(route.totals.distance_m),
			formatDuration(route.totals.duration_s),
			`↑\u00a0${formatHeight(route.totals.ascent_m)}`,
			formatSAC(route.totals.sac_grade, route.totals.sac_max)
		].join(' · ')
	);
	const imageUrl = $derived(
		`${page.url.origin}/api/v1/routes/${route.id}/og.png?v=${route.version}${token ? `&t=${token}` : ''}`
	);

	let base = $state<BaseMapId>('landeskarte');
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib = $state<typeof MapLibre>();
	let hoverIndex = $state<number>();
	let travelTrips = $state<Trip[]>([]);
	let routePois = $state<Poi[]>([]);
	let confirmDelete = $state(false);
	// Stage routes have their photos on the journey; an earlier version shows
	// the line only.
	// svelte-ignore state_referenced_locally
	const gallery = route.journey_id || revision ? undefined : new Gallery('routes', route.id, token);
	// svelte-ignore state_referenced_locally
	const community = gallery && new Community('routes', route.id, token);
	let changed = $state(false);
	// Tabs and menu answer only once hydrated: a click before would be lost.
	const hydrated = new Hydrated();
	let menu = $state(false);
	let menuBox = $state<HTMLElement>();
	let copied = $state(false);

	// Read-only planner: renders the stored legs, never routes. Loaded once;
	// the page re-creates this component for another route ({#key}).
	const planner = new Planner(() => Promise.reject(new Error('read-only')));
	// svelte-ignore state_referenced_locally
	planner.load({ profile: route.profile as Profile, anchors: route.anchors, legs: route.legs });
	const hover = $derived.by((): [number, number] | undefined => {
		const c = hoverIndex !== undefined ? planner.line.coordinates[hoverIndex] : undefined;
		return c ? [c[0], c[1]] : undefined;
	});

	function onready(m: MapLibreMap, l: typeof MapLibre) {
		map = m;
		lib = l;
		const coords = planner.line.coordinates;
		if (coords.length === 0) return; // a short hike of someone else: nothing shown
		const bounds = coords.reduce(
			(b, c) => b.extend([c[0], c[1]]),
			new l.LngLatBounds([coords[0][0], coords[0][1]], [coords[0][0], coords[0][1]])
		);
		m.fitBounds(bounds, { padding: { top: 60, bottom: 200, left: 60, right: 60 }, duration: 0 });
	}

	// Details on demand: the rest of the page in tabs, the counts beside them.
	type Tab = 'overview' | 'along' | 'travel' | 'photos';
	let tab = $state<Tab>('overview');
	// A stage's way there and back is its journey's (from home, before the first and after the last).
	const travel = $derived(!!user && !revision && !route.journey_id && route.legs.length > 0);
	const tabs = $derived(
		[
			{ id: 'overview' as Tab, label: m.route_tab_overview() },
			routePois.length > 0 && { id: 'along' as Tab, label: m.pois_title(), n: routePois.length },
			travel && { id: 'travel' as Tab, label: m.route_tab_travel() },
			gallery && { id: 'photos' as Tab, label: m.photos_title(), n: gallery.photos.length }
		].filter((t) => !!t)
	);
	// Off marked trails all the way: said in words, not as a bar of one colour.
	const offTrail = $derived.by(() => {
		const parts = breakdownParts(planner.totals.trails, Object.keys(TRAIL_COLOR));
		return parts.length === 1 && parts[0].key === 'none';
	});

	/** The page's address with the share token, if there is one, to send. */
	async function share() {
		const t = token ?? (route.visibility === 'unlisted' ? route.share_token : undefined);
		const url = `${page.url.origin}${page.url.pathname}${t ? `?t=${encodeURIComponent(t)}` : ''}`;
		if (navigator.share) {
			await navigator.share({ title: route.title, url }).catch(() => {});
			return;
		}
		await navigator.clipboard.writeText(url);
		copied = true;
		setTimeout(() => (copied = false), 2000);
	}

	async function restore(version: number) {
		const { response } = await api().POST('/routes/{id}/revisions/{version}/restore', {
			params: { path: { id: route.id, version }, header: { 'If-Match': `"${route.version}"` } }
		});
		if (response.ok) await goto(resolve('/routes/[id]', { id: route.id }), { invalidateAll: true });
		else changed = response.status === 412;
	}

	const button =
		'inline-flex h-9 min-w-9 items-center justify-center gap-1.5 rounded-lg border border-stone-300 px-2.5 hover:bg-stone-100 disabled:opacity-60';
	const item = 'flex w-full rounded-lg px-2.5 py-2 text-left hover:bg-stone-100';

	async function remove() {
		const { response } = await api().DELETE('/routes/{id}', { params: { path: { id: route.id } } });
		if (response.ok) await goto(resolve('/routes'));
	}
</script>

<svelte:window
	onclick={(e) => {
		// The path as clicked: «Löschen» is gone from the page by now.
		if (menu && menuBox && !e.composedPath().includes(menuBox)) {
			menu = false;
			confirmDelete = false;
		}
	}}
	onkeydown={(e) => {
		if (e.key === 'Escape') menu = false;
	}}
/>

<Seo
	title={route.title}
	description={`${m.seo_route_description({ stats: summary })} ${route.description ?? ''}`}
	image={imageUrl}
	index={route.visibility === 'public' && !route.journey_id && !revision}
/>

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map && lib}
			<RouteLayers {map} {lib} {planner} {hover} editable={false} />
			{#if gallery}<PhotoPins {map} {lib} {gallery} />{/if}
			<PoiPins {map} {lib} pois={routePois} />
			<TravelLayers {map} {lib} trips={travelTrips} />
		{/if}
		<ProfileDock>
			<ElevationProfile line={planner.line} bind:hover={hoverIndex} />
		</ProfileDock>
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col overflow-y-auto border-t border-stone-200 bg-surface md:w-96 md:flex-none md:border-t-0 md:border-l"
	>
		<div class="flex flex-col gap-3 p-4 pb-3">
			{#if revision}
				<div
					class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm dark:border-amber-800 dark:bg-amber-950/40"
					data-testid="revision"
				>
					<p>
						{m.revision_shown({
							date: savedAt(revision.saved_at),
							user: revision.saved_by || m.revision_someone()
						})}
					</p>
					<div class="mt-2 flex flex-wrap items-center gap-3">
						<button
							type="button"
							class="rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover"
							onclick={() => restore(revision.version)}>{m.revision_restore()}</button
						>
						<a href={resolve('/routes/[id]', { id: route.id })} class="text-accent-ink underline"
							>{m.revision_current()}</a
						>
					</div>
					{#if changed}<p class="mt-2 text-red-700" role="alert">{m.revision_changed()}</p>{/if}
				</div>
			{/if}
			<div class="flex items-start justify-between gap-2">
				<div class="min-w-0">
					<h1 class="text-xl font-semibold" data-testid="route-title">{route.title}</h1>
					<p class="text-sm text-stone-500">
						{#if route.visibility === 'public'}
							<a
								href={resolve('/u/[username]', { username: route.owner_username })}
								class="hover:underline">{m.route_by({ user: route.owner_username })}</a
							>
						{:else}
							{m.route_by({ user: route.owner_username })}
						{/if}
					</p>
				</div>
				{#if !revision}
					<!-- What is done now and then: printing, collections, versions, deleting. -->
					<div class="relative shrink-0" bind:this={menuBox}>
						<button
							type="button"
							class={button}
							aria-label={m.route_more()}
							aria-expanded={menu}
							aria-controls="route-menu"
							disabled={!hydrated.value}
							onclick={() => (menu = !menu)}
							data-testid="route-menu">⋯</button
						>
						<div
							id="route-menu"
							class="absolute top-11 right-0 z-20 flex w-64 flex-col rounded-xl border border-stone-200 bg-surface p-1.5 text-sm shadow-lg"
							hidden={!menu}
						>
							{#if route.legs.length > 0}
								<!-- The share token rides along; resolve() cannot express query strings. -->
								<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
								<a
									href="{resolve('/routes/[id]/sheet', { id: route.id })}{token
										? `?t=${token}`
										: ''}"
									class={item}
									data-testid="sheet-link">{m.sheet_link()}</a
								>
							{/if}
							<OpenInApp kind="routes" id={route.id} class={item} />
							{#if user && !route.journey_id}
								<div class="px-1.5 py-1"><AddToCollection kind="route" id={route.id} /></div>
							{/if}
							{#if route.can_edit}
								<div class="px-2.5 py-2"><Revisions id={route.id} /></div>
								<hr class="my-1 border-stone-200" />
								{#if confirmDelete}
									<button
										type="button"
										class="{item} bg-red-700 font-medium text-white hover:bg-red-800"
										onclick={remove}
									>
										{m.route_delete_confirm()}
									</button>
								{:else}
									<button
										type="button"
										class="{item} text-red-700 dark:text-red-400"
										onclick={() => (confirmDelete = true)}
									>
										{m.route_delete()}
									</button>
								{/if}
							{/if}
						</div>
					</div>
				{/if}
			</div>
			{#if route.tags.length > 0 || route.hike}
				<div class="-mt-2">
					<TagChips tags={route.tags} />
					{#if route.hike}
						<p class="text-sm text-stone-600" data-testid="hike">
							{m.route_hiked({
								date: hikeDate(route.hike.at),
								duration: formatDuration(route.hike.duration_s)
							})}
							{#if route.hike.planned_route_id}
								·
								<a
									href={resolve('/routes/[id]', { id: route.hike.planned_route_id })}
									class="text-accent-ink underline">{m.route_hiked_planned()}</a
								>
							{/if}
						</p>
						<p class="text-sm text-stone-600" data-testid="hike-privacy">
							{#if route.can_edit}
								{m.route_privacy_owner()}
							{:else if route.legs.length === 0}
								{m.route_privacy_all()}
							{:else}
								{m.route_privacy_others()}
							{/if}
						</p>
					{/if}
				</div>
			{/if}
			{#if !revision}
				<!-- One main action; the others small beside it. -->
				<div class="flex flex-wrap gap-2 text-sm">
					{#if route.can_edit}
						<a
							href={resolve('/plan/[id]', { id: route.id })}
							class="{button} border-accent bg-accent font-semibold text-on-accent hover:bg-accent-hover"
						>
							✎ {m.route_edit()}
						</a>
					{/if}
					<!-- API download, not a page: resolve() does not apply. -->
					<!-- eslint-disable svelte/no-navigation-without-resolve -->
					<a
						href="/api/v1/routes/{route.id}/gpx"
						download
						class={button}
						aria-label={m.route_gpx()}
						title={m.route_gpx()}>↓ GPX</a
					>
					<!-- eslint-enable svelte/no-navigation-without-resolve -->
					{#if community}
						<button
							type="button"
							class="{button} {community.social?.liked ? 'text-rose-700 dark:text-rose-400' : ''}"
							aria-pressed={community.social?.liked ?? false}
							disabled={!user || !community.social || community.busy}
							title={user ? undefined : m.community_login_to_like()}
							onclick={() => community.like()}
							data-testid="route-like"
							>{community.social?.liked ? '♥' : '♡'} {m.route_like()}</button
						>
					{/if}
					<button
						type="button"
						class={button}
						aria-label={m.route_share()}
						title={copied ? m.share_copied() : m.route_share()}
						onclick={share}
						data-testid="route-share"
					>
						{#if copied}{m.share_copied()}{:else}
							<svg
								width="16"
								height="16"
								viewBox="0 0 24 24"
								fill="none"
								stroke="currentColor"
								stroke-width="2"
								stroke-linecap="round"
								stroke-linejoin="round"
								aria-hidden="true"
								><path d="M12 15V3M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" /></svg
							>
						{/if}
					</button>
				</div>
			{/if}
			{#if route.legs.length > 0}
				<StatsPanel totals={planner.totals} pace={user?.speed_factor ?? 1} breakdown={false} />
			{/if}
		</div>

		{#if tabs.length > 1}
			<div
				class="sticky top-0 z-10 flex shrink-0 gap-1 overflow-x-auto border-b border-stone-200 bg-surface px-3 text-sm"
				role="tablist"
				aria-label={m.route_sections()}
			>
				{#each tabs as t (t.id)}
					<button
						type="button"
						role="tab"
						id="tab-{t.id}"
						aria-selected={tab === t.id}
						aria-controls="pane-{t.id}"
						disabled={!hydrated.value}
						class="-mb-px border-b-2 px-2 py-2.5 whitespace-nowrap {tab === t.id
							? 'border-accent font-semibold text-stone-900'
							: 'border-transparent text-stone-500 hover:text-stone-900'}"
						onclick={() => (tab = t.id)}
						data-testid="tab-{t.id}"
					>
						{t.label}{#if t.n !== undefined}<span
								class="ml-1 rounded-full bg-stone-100 px-1.5 text-xs font-normal tabular-nums"
								>{t.n}</span
							>{/if}
					</button>
				{/each}
			</div>
		{/if}

		<!-- Every tab stays mounted: the map shows what each one loads. -->
		<div
			class="flex flex-col gap-3 p-4"
			role="tabpanel"
			id="pane-overview"
			aria-labelledby="tab-overview"
			hidden={tab !== 'overview'}
		>
			{#if route.description}<p class="text-sm whitespace-pre-line">{route.description}</p>{/if}
			{#if offTrail}
				<div
					class="flex gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2.5 text-sm dark:border-amber-800 dark:bg-amber-950/40"
					data-testid="off-trail"
				>
					<span aria-hidden="true">⚠️</span>
					<p>
						<span class="font-semibold">{m.off_trail_title()}</span><br />
						<span class="text-xs text-stone-600"
							>{m.off_trail_all({ distance: formatDistance(planner.totals.distanceM) })}</span
						>
					</p>
				</div>
			{/if}
			<Notices {notices} />
			<ProtectedAreas {areas} failed={areasFailed} />
			{#if !revision}<RouteWeather id={route.id} {token} />{/if}
			{#if route.legs.length > 0}
				<section class="rounded-xl border border-stone-200 p-3" data-testid="breakdowns">
					<h3
						class="mb-2 flex items-baseline justify-between text-xs font-medium tracking-wide text-stone-500 uppercase"
					>
						{m.breakdown_title()}
						<span class="font-normal tracking-normal normal-case"
							>{formatDistance(planner.totals.distanceM)}</span
						>
					</h3>
					<Breakdowns totals={planner.totals} />
				</section>
			{/if}
		</div>
		{#if !revision}
			<div
				class="p-4"
				role="tabpanel"
				id="pane-along"
				aria-labelledby="tab-along"
				hidden={tab !== 'along'}
			>
				<Pois id={route.id} {token} onload={(p) => (routePois = p)} />
			</div>
		{/if}
		{#if travel}
			<div
				class="p-4"
				role="tabpanel"
				id="pane-travel"
				aria-labelledby="tab-travel"
				hidden={tab !== 'travel'}
			>
				<Travel
					kind="routes"
					id={route.id}
					{token}
					ends={routeEnds(route, { start: m.place_start(), end: m.place_end() })}
					onshow={(t) => (travelTrips = t)}
				/>
			</div>
		{/if}
		{#if gallery && community}
			<div
				class="flex flex-col gap-3 p-4"
				role="tabpanel"
				id="pane-photos"
				aria-labelledby="tab-photos"
				hidden={tab !== 'photos'}
			>
				<Photos {gallery} loggedIn={!!user} />
				<Social {community} {user} />
			</div>
		{/if}
	</aside>
</main>
