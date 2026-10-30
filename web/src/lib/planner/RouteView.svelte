<script lang="ts">
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me, type Revision, type Route } from '#lib/api/client.js';
	import LayerSwitcher from '#lib/map/LayerSwitcher.svelte';
	import Map from '#lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { hikeDate, savedAt } from '#lib/util/locale.js';
	import AddToCollection from '#lib/collections/AddToCollection.svelte';
	import { Community } from '#lib/community/community.svelte.js';
	import Social from '#lib/community/Social.svelte';
	import { Gallery } from '#lib/photos/gallery.svelte.js';
	import PhotoPins from '#lib/photos/PhotoPins.svelte';
	import Photos from '#lib/photos/Photos.svelte';
	import TagChips from '#lib/tags/TagChips.svelte';
	import { breakdownParts } from './breakdown';
	import Breakdowns from './Breakdowns.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import ProfileDock from './ProfileDock.svelte';
	import Revisions from './Revisions.svelte';
	import RouteDraw from './RouteDraw.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import StatsPanel from './StatsPanel.svelte';
	import ProtectedAreas from '#lib/areas/ProtectedAreas.svelte';
	import Notices from '#lib/areas/Notices.svelte';
	import SnowAlong from '#lib/areas/SnowAlong.svelte';
	import LineHighlight from '#lib/map/LineHighlight.svelte';
	import Pois from '#lib/map/Pois.svelte';
	import PoiPins from '#lib/map/PoiPins.svelte';
	import type { Poi } from '#lib/map/places.js';
	import RouteWeather from '#lib/weather/RouteWeather.svelte';
	import OpenInApp from '#lib/sharing/OpenInApp.svelte';
	import Travel from '#lib/travel/Travel.svelte';
	import TravelLayers from '#lib/travel/TravelLayers.svelte';
	import { routeEnds } from '#lib/travel/travel.js';
	import type { Trip } from '#lib/api/client.js';
	import type { Notice, ProtectedArea, SnowAlong as Snow, Steepness } from '#lib/api/client.js';
	import { onMount } from 'svelte';
	import { mainAction, menuItem, primaryButtonSmall } from '#lib/components/actions.js';
	import MoreMenu from '#lib/components/MoreMenu.svelte';
	import CopyButton from '#lib/official/CopyButton.svelte';
	import OfficialCredit from '#lib/official/OfficialCredit.svelte';
	import ShareButton from '#lib/components/ShareButton.svelte';
	import TabBar from '#lib/components/TabBar.svelte';
	import CommentsButton from '#lib/community/CommentsButton.svelte';
	import LikeButton from '#lib/community/LikeButton.svelte';
	import DoneButton from '#lib/done/DoneButton.svelte';
	import { STEEP_COLORS, STEEP_FROM, TRAIL_COLOR } from './colors';
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
	let snow = $state<Snow>();
	let steepness = $state<Steepness>();
	// A part of the line picked in a list, shown on the map.
	let picked = $state<number[][][]>([]);
	onMount(async () => {
		const params = { path: { id: route.id }, query: token ? { t: token } : {} };
		api()
			.GET('/routes/{id}/snow', { params })
			.then(({ data }) => (snow = data));
		api()
			.GET('/routes/{id}/steepness', { params })
			.then(({ data }) => (steepness = data));
		const { data } = await api().GET('/routes/{id}/areas', { params });
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
	let poiHighlight = $state<number[][]>([]);
	let confirmDelete = $state(false);
	// Stage routes have their photos on the journey; an earlier version shows
	// the line only.
	// svelte-ignore state_referenced_locally
	const gallery = route.journey_id || revision ? undefined : new Gallery('routes', route.id, token);
	// svelte-ignore state_referenced_locally
	const community = gallery && new Community('routes', route.id, token);
	let changed = $state(false);

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
	let tab = $state('overview');
	// A stage's way there and back is its journey's (from home, before the first and after the last).
	const travel = $derived(!!user && !revision && !route.journey_id && route.legs.length > 0);
	const tabs = $derived(
		[
			{ id: 'overview', label: m.route_tab_overview() },
			routePois.length > 0 && { id: 'along', label: m.pois_title(), n: routePois.length },
			travel && { id: 'travel', label: m.route_tab_travel() },
			gallery && { id: 'photos', label: m.photos_title(), n: gallery.photos.length },
			community && {
				id: 'comments',
				label: m.comments_tab(),
				n: community.social?.comments.length
			}
		].filter((t) => !!t)
	);
	function openComments() {
		tab = 'comments';
		document.getElementById('tab-comments')?.scrollIntoView({ block: 'nearest' });
	}
	// Off marked trails all the way: said in words, not as a bar of one colour.
	const offTrail = $derived.by(() => {
		const parts = breakdownParts(planner.totals.trails, Object.keys(TRAIL_COLOR));
		return parts.length === 1 && parts[0].key === 'none';
	});

	async function restore(version: number) {
		const { response } = await api().POST('/routes/{id}/revisions/{version}/restore', {
			params: { path: { id: route.id, version }, header: { 'If-Match': `"${route.version}"` } }
		});
		if (response.ok) await goto(resolve('/routes/[id]', { id: route.id }), { refreshAll: true });
		else changed = response.status === 412;
	}

	async function remove() {
		const { response } = await api().DELETE('/routes/{id}', { params: { path: { id: route.id } } });
		if (response.ok) await goto(resolve('/routes'));
	}
</script>

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
			<RouteDraw {map} line={planner.line.coordinates} />
			{#if gallery}<PhotoPins {map} {lib} {gallery} />{/if}
			<PoiPins {map} {lib} pois={routePois} highlight={poiHighlight} />
			<TravelLayers {map} {lib} trips={travelTrips} />
			<LineHighlight {map} {lib} parts={picked} />
		{/if}
		<ProfileDock>
			<ElevationProfile
				line={planner.line}
				bind:hover={hoverIndex}
				steep={steepness?.known ? steepness.stretches : undefined}
			/>
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
							class={primaryButtonSmall}
							onclick={() => restore(revision.version)}>{m.revision_restore()}</button
						>
						<a href={resolve('/routes/[id]', { id: route.id })} class="text-accent-ink underline"
							>{m.revision_current()}</a
						>
					</div>
					{#if changed}<p class="mt-2 text-red-700 dark:text-red-400" role="alert">
							{m.revision_changed()}
						</p>{/if}
				</div>
			{/if}
			<div class="flex items-start justify-between gap-2">
				<div class="min-w-0">
					<h1 class="text-xl font-semibold" data-testid="route-title">{route.title}</h1>
					{#if route.official}
						<OfficialCredit official={route.official} />
					{:else}
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
					{/if}
				</div>
				{#if !revision}
					<!-- What is done now and then: printing, GPX, collections, versions, deleting. -->
					<MoreMenu testid="route-menu" onclose={() => (confirmDelete = false)}>
						{#if route.legs.length > 0}
							<!-- The share token rides along; resolve() cannot express query strings. -->
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
							<a
								href="{resolve('/routes/[id]/sheet', { id: route.id })}{token ? `?t=${token}` : ''}"
								class={menuItem}
								data-testid="sheet-link">{m.sheet_link()}</a
							>
						{/if}
						<!-- API download, not a page: resolve() does not apply. -->
						<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
						<a href="/api/v1/routes/{route.id}/gpx" download class={menuItem}>{m.route_gpx()}</a>
						<OpenInApp kind="routes" id={route.id} class={menuItem} />
						{#if user && !route.journey_id}
							<div class="px-1.5 py-1"><AddToCollection kind="route" id={route.id} /></div>
						{/if}
						{#if route.can_edit}
							<div class="px-2.5 py-2"><Revisions id={route.id} /></div>
							<hr class="my-1 border-stone-200" />
							{#if confirmDelete}
								<button
									type="button"
									class="{menuItem} bg-red-700 font-medium text-white hover:bg-red-800"
									onclick={remove}
								>
									{m.route_delete_confirm()}
								</button>
							{:else}
								<button
									type="button"
									class="{menuItem} text-red-700 dark:text-red-400"
									onclick={() => (confirmDelete = true)}
								>
									{m.route_delete()}
								</button>
							{/if}
						{/if}
					</MoreMenu>
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
						<a href={resolve('/plan/[id]', { id: route.id })} class={mainAction}>
							✎ {m.route_edit()}
						</a>
					{:else if !route.hike && route.legs.length > 0}
						<!-- Someone else's planned route: one's own copy to change. -->
						<CopyButton kind="routes" id={route.id} {token} {user} />
					{/if}
					{#if community}
						<LikeButton {community} {user} testid="route-like" />
						<CommentsButton {community} onclick={openComments} />
					{/if}
					{#if user && !route.journey_id}
						<DoneButton
							kind="routes"
							id={route.id}
							{token}
							doneOn={route.done_on}
							marked={route.done_marked}
							by="hike"
						/>
					{/if}
					<ShareButton
						title={route.title}
						token={token ?? (route.visibility === 'unlisted' ? route.share_token : undefined)}
						testid="route-share"
					/>
				</div>
			{/if}
			{#if route.legs.length > 0}
				<StatsPanel totals={planner.totals} pace={user?.speed_factor ?? 1} breakdown={false} />
			{/if}
		</div>

		{#if tabs.length > 1}<TabBar {tabs} bind:current={tab} />{/if}

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
			{#if steepness?.known}
				<!-- How much is steep, and what the band under the profile means. -->
				<p
					class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-stone-600"
					data-testid="steep-along"
				>
					{#if steepness.steep_m >= 100}<span class="font-medium text-stone-800"
							>{m.steep_along({ distance: formatDistance(steepness.steep_m) })}</span
						>{/if}
					<span class="text-xs">{m.steep_band()}</span>
					{#each [1, 2, 3] as c (c)}<span class="inline-flex items-center gap-1 text-xs"
							><span class="inline-block h-1.5 w-4 rounded-sm" style:background={STEEP_COLORS[c]}
							></span>≥ {STEEP_FROM[c]}</span
						>{/each}
				</p>
			{/if}
			<Notices {notices} onshow={(p) => (picked = p)} />
			<ProtectedAreas {areas} failed={areasFailed} onshow={(p) => (picked = p)} />
			<SnowAlong {snow} onshow={(p) => (picked = p)} />
			{#if !revision}<RouteWeather id={route.id} {token} />{/if}
			{#if route.legs.length > 0}
				<section class="rounded-xl border border-stone-200 p-3" data-testid="breakdowns">
					<h2
						class="mb-2 flex items-baseline justify-between text-xs font-medium tracking-wide text-stone-500 uppercase"
					>
						{m.breakdown_title()}
						<span class="font-normal tracking-normal normal-case"
							>{formatDistance(planner.totals.distanceM)}</span
						>
					</h2>
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
				<Pois
					id={route.id}
					{token}
					onload={(p) => (routePois = p)}
					onhover={(at) => (poiHighlight = at)}
				/>
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
			</div>
			<!-- Likes go with the comments; mounted while hidden, so the counts load. -->
			<div
				class="flex flex-col gap-3 p-4"
				role="tabpanel"
				id="pane-comments"
				aria-labelledby="tab-comments"
				hidden={tab !== 'comments'}
			>
				<Social {community} {user} />
			</div>
		{/if}
	</aside>
</main>
