<script lang="ts">
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me, type Route } from '$lib/api/client';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import { hikeDate } from '$lib/util/locale';
	import AddToCollection from '$lib/collections/AddToCollection.svelte';
	import Social from '$lib/community/Social.svelte';
	import { Gallery } from '$lib/photos/gallery.svelte';
	import PhotoPins from '$lib/photos/PhotoPins.svelte';
	import Photos from '$lib/photos/Photos.svelte';
	import TagChips from '$lib/tags/TagChips.svelte';
	import ElevationProfile from './ElevationProfile.svelte';
	import RouteLayers from './RouteLayers.svelte';
	import StatsPanel from './StatsPanel.svelte';
	import { Planner } from './planner.svelte';
	import { formatDistance, formatDuration, formatSAC, type Profile } from './route';

	let { route, token, user }: { route: Route; token?: string; user: Me | null } = $props();
	// Link previews (Signal, WhatsApp, Slack …) read these tags from the SSR page.
	const summary = $derived(
		[
			formatDistance(route.totals.distance_m),
			formatDuration(route.totals.duration_s),
			`↑ ${Math.round(route.totals.ascent_m)} m`,
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
	let confirmDelete = $state(false);
	// Stage routes have their photos on the journey.
	// svelte-ignore state_referenced_locally
	const gallery = route.journey_id ? undefined : new Gallery('routes', route.id, token);

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
		const bounds = coords.reduce(
			(b, c) => b.extend([c[0], c[1]]),
			new l.LngLatBounds([coords[0][0], coords[0][1]], [coords[0][0], coords[0][1]])
		);
		m.fitBounds(bounds, { padding: { top: 60, bottom: 200, left: 60, right: 60 }, duration: 0 });
	}

	async function remove() {
		const { response } = await api().DELETE('/routes/{id}', { params: { path: { id: route.id } } });
		if (response.ok) await goto(resolve('/routes'));
	}
</script>

<svelte:head>
	<title>{route.title} · odysgeh</title>
	<meta name="description" content={summary} />
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content="odysgeh" />
	<meta property="og:title" content={route.title} />
	<meta property="og:description" content={summary} />
	<meta property="og:url" content={page.url.href} />
	<meta property="og:image" content={imageUrl} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
</svelte:head>

<main class="flex min-h-0 flex-1">
	<section class="relative flex-1">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map && lib}
			<RouteLayers {map} {lib} {planner} {hover} editable={false} />
			{#if gallery}<PhotoPins {map} {lib} {gallery} />{/if}
		{/if}
		<div
			class="absolute right-12 bottom-8 left-2 z-10 rounded-md bg-white/95 px-2 py-1 shadow ring-1 ring-stone-300"
		>
			<ElevationProfile line={planner.line} bind:hover={hoverIndex} />
		</div>
	</section>

	<aside class="flex w-80 flex-col gap-4 overflow-y-auto border-l border-stone-200 bg-white p-4">
		<div>
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
			<div class="mt-1"><TagChips tags={route.tags} /></div>
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
							class="text-emerald-800 underline">{m.route_hiked_planned()}</a
						>
					{/if}
				</p>
			{/if}
		</div>
		{#if route.description}<p class="text-sm whitespace-pre-line">{route.description}</p>{/if}
		{#if route.can_edit}
			<div class="flex gap-2 text-sm">
				<a
					href={resolve('/plan/[id]', { id: route.id })}
					class="rounded-md bg-emerald-700 px-3 py-1.5 text-white hover:bg-emerald-800"
				>
					{m.route_edit()}
				</a>
				{#if confirmDelete}
					<button
						type="button"
						class="rounded-md bg-red-700 px-3 py-1.5 text-white"
						onclick={remove}
					>
						{m.route_delete_confirm()}
					</button>
				{:else}
					<button
						type="button"
						class="rounded-md px-3 py-1.5 ring-1 ring-stone-300"
						onclick={() => (confirmDelete = true)}
					>
						{m.route_delete()}
					</button>
				{/if}
			</div>
		{/if}
		<!-- API download, not a page: resolve() does not apply. -->
		<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
		<a href="/api/v1/routes/{route.id}/gpx" download class="text-sm text-emerald-800 underline"
			>{m.route_gpx()}</a
		>
		<StatsPanel totals={planner.totals} pace={user?.speed_factor ?? 1} />
		{#if user && !route.journey_id}
			<AddToCollection kind="route" id={route.id} />
		{/if}
		{#if gallery}
			<Photos {gallery} loggedIn={!!user} />
			<Social kind="routes" id={route.id} {token} {user} />
		{/if}
	</aside>
</main>
