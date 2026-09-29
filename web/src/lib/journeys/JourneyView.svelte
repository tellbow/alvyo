<script lang="ts">
	import OpenInApp from '$lib/sharing/OpenInApp.svelte';
	import type { Map as MapLibreMap } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import {
		api,
		type Journey,
		type Me,
		type Notice,
		type ProtectedArea,
		type RouteSummary,
		type StagePatch,
		type Trip
	} from '$lib/api/client';
	import LayerSwitcher from '$lib/map/LayerSwitcher.svelte';
	import Map from '$lib/map/Map.svelte';
	import type { BaseMapId, OverlayId } from '$lib/map/styles';
	import { m } from '$lib/paraglide/messages';
	import { getLocale } from '$lib/paraglide/runtime';
	import ElevationProfile from '$lib/planner/ElevationProfile.svelte';
	import ProfileDock from '$lib/planner/ProfileDock.svelte';
	import StatsPanel from '$lib/planner/StatsPanel.svelte';
	import ProtectedAreas from '$lib/areas/ProtectedAreas.svelte';
	import Notices from '$lib/areas/Notices.svelte';
	import JourneyWeather from '$lib/weather/JourneyWeather.svelte';
	import {
		formatDistance,
		formatDuration,
		formatHeight,
		formatSAC,
		type Profile3,
		type Totals
	} from '$lib/planner/route';
	import Seo from '$lib/seo/Seo.svelte';
	import { STAGE_RUN_COLORS } from './colors';
	import Connections from './Connections.svelte';
	import { transferStops } from './transfer';
	import JourneyLayers from './JourneyLayers.svelte';
	import { sbbTimetableUrl } from './sbb';
	import AddToCollection from '$lib/collections/AddToCollection.svelte';
	import Social from '$lib/community/Social.svelte';
	import { Gallery } from '$lib/photos/gallery.svelte';
	import PhotoPins from '$lib/photos/PhotoPins.svelte';
	import Photos from '$lib/photos/Photos.svelte';
	import SharePanel from '$lib/sharing/SharePanel.svelte';
	import StageCard from './StageCard.svelte';
	import JourneyPeople from './JourneyPeople.svelte';
	import JourneyReminders from './JourneyReminders.svelte';
	import { stagePeople } from './people';
	import type { Person } from '$lib/api/client';
	import Travel from '$lib/travel/Travel.svelte';
	import TravelLayers from '$lib/travel/TravelLayers.svelte';
	import { journeyEnds } from '$lib/travel/travel';
	import TagChips from '$lib/tags/TagChips.svelte';
	import TagInput from '$lib/tags/TagInput.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { choose } from '$lib/util/choose';

	let {
		journey: initial,
		token,
		user
	}: { journey: Journey; token?: string; user: Me | null } = $props();

	// The API returns the whole journey after every change; it replaces this.
	// svelte-ignore state_referenced_locally
	let journey = $state(initial);
	// Buttons that only toggle page state do nothing before hydration.
	const hydrated = new Hydrated();
	const canEdit = $derived(journey.can_edit);
	const isOwner = $derived(journey.role === 'owner');

	let base = $state<BaseMapId>('landeskarte');
	// The connections from and to home shown on the map.
	let travelTrips = $state<Trip[]>([]);
	let overlays = $state<OverlayId[]>(['wanderwege']);
	let map = $state<MapLibreMap>();
	let lib = $state<typeof MapLibre>();
	// svelte-ignore state_referenced_locally
	const gallery = new Gallery('journeys', initial.id, token);
	let hoverIndex = $state<number>();
	let confirming = $state(false); // deleting the journey
	let myRoutes = $state<RouteSummary[]>([]);
	let areas = $state<ProtectedArea[]>();
	let notices = $state<Notice[]>();
	let areasFailed = $state(false);
	// Who comes along (for those who may see it), shown on their stages too.
	let people = $state<Person[]>([]);
	// The stages' planned days, to say when an area's rules apply then.
	const plannedDays = $derived(
		journey.stage_list.flatMap((s) => (s.planned_date ? [s.planned_date] : []))
	);

	/** Asked again when a stage route changes (the version of the journey does not). */
	const routeKey = $derived(journey.stage_list.map((s) => s.route?.id ?? '').join());
	$effect(() => {
		void routeKey;
		// Not journey itself: every change replaces it.
		const id = untrack(() => journey.id);
		let stale = false;
		api()
			.GET('/journeys/{id}/areas', {
				params: { path: { id }, query: token ? { t: token } : {} }
			})
			.then(({ data }) => {
				if (stale) return;
				areas = data?.areas;
				notices = data?.notices;
				areasFailed = !data;
			});
		return () => {
			stale = true;
		};
	});
	let error = $state('');

	/** The combined profile in the shape ElevationProfile draws, coloured per stage. */
	const profile = $derived.by((): Profile3 => {
		const p = journey.profile;
		const runs = p.breaks.map((from, k) => {
			const stageIndex = routedStageIndex(k);
			const to = k + 1 < p.breaks.length ? p.breaks[k + 1] : p.distance.length - 1;
			return { from, to, value: `S${stageIndex % 6}` };
		});
		return { coordinates: p.points, distance: p.distance, sac: runs };
	});
	const hover = $derived.by((): [number, number] | undefined => {
		const c = hoverIndex !== undefined ? journey.profile.points[hoverIndex] : undefined;
		return c ? [c[0], c[1]] : undefined;
	});
	const totals = $derived<Totals>({
		distanceM: journey.totals.distance_m,
		ascentM: journey.totals.ascent_m,
		descentM: journey.totals.descent_m,
		durationS: journey.totals.duration_s,
		durationReverseS: journey.totals.duration_reverse_s,
		eleMinM: journey.totals.ele_min_m,
		eleMaxM: journey.totals.ele_max_m,
		sacGrade: journey.totals.sac_grade,
		sacMax: journey.totals.sac_max,
		sacBreakdown: {},
		unofficialM: 0,
		surfaces: {},
		wayTypes: {},
		trails: {}
	});
	const shareUrl = $derived(
		isOwner && journey.share_token
			? `${page.url.origin}/journeys/${journey.id}?t=${journey.share_token}`
			: ''
	);
	const q = $derived(token ? `?t=${token}` : '');

	/** Index in stage_list of the k-th stage that has a route. */
	function routedStageIndex(k: number): number {
		let seen = -1;
		for (let i = 0; i < journey.stage_list.length; i++) {
			if (journey.stage_list[i].route && ++seen === k) return i;
		}
		return 0;
	}

	function onready(m: MapLibreMap, l: typeof MapLibre) {
		map = m;
		lib = l;
		const pts = journey.stage_list.flatMap((s) => s.route?.line ?? []);
		if (pts.length === 0) return;
		const b = pts.reduce(
			(acc, c) => acc.extend([c[0], c[1]]),
			new l.LngLatBounds([pts[0][0], pts[0][1]], [pts[0][0], pts[0][1]])
		);
		m.fitBounds(b, { padding: { top: 60, bottom: 200, left: 60, right: 60 }, duration: 0 });
	}

	// Changes are sent one after another: every response is the whole journey,
	// so a slower earlier response must not overwrite a later change.
	let queue: Promise<unknown> = Promise.resolve();

	function mutate(
		call: () => Promise<{ data?: Journey; response: Response }> | undefined,
		failed: (r: Response) => string = () => m.error_generic()
	) {
		const run = queue.then(async () => {
			const request = call();
			if (!request) return journey; // nothing left to change
			error = '';
			const { data, response } = await request;
			if (data) journey = data;
			else error = failed(response);
			return data;
		});
		queue = run.catch(() => {});
		return run;
	}

	const path = (stage: string) => ({ params: { path: { id: journey.id, stage } } });

	function transferUrl(i: number): string | undefined {
		const t = transferStops(journey, i);
		if (!t) return undefined;
		const date = journey.stage_list[i].planned_date;
		return sbbTimetableUrl({ from: t.from.name, to: t.to.name, date, locale: getLocale() });
	}

	let showConnections = $state<string>(); // stage id

	function patchStage(stage: string, body: StagePatch) {
		return mutate(
			() => {
				// The stage as it is once earlier changes are through.
				const version = journey.stage_list.find((s) => s.id === stage)?.version;
				if (version === undefined) return undefined;
				return api().PATCH('/journeys/{id}/stages/{stage}', {
					params: {
						path: { id: journey.id, stage },
						header: { 'If-Match': `"${version}"` }
					},
					body
				});
			},
			(r) => {
				if (r.status !== 412) return m.error_generic();
				// Someone else changed the stage: show theirs, keep nothing of ours.
				void reload();
				return m.stage_conflict();
			}
		);
	}

	// Counts conflicts: the stage cards are drawn anew, so no field keeps
	// text that was not saved.
	let conflicts = $state(0);

	async function reload() {
		const { data } = await api().GET('/journeys/{id}', { params: { path: { id: journey.id } } });
		if (data) journey = data as Journey;
		conflicts++;
	}

	async function addStage(copyRouteId?: string) {
		const j = await mutate(() =>
			api().POST('/journeys/{id}/stages', {
				params: { path: { id: journey.id } },
				body: copyRouteId ? { copy_route_id: copyRouteId } : {}
			})
		);
		const added = j?.stage_list.at(-1);
		if (added && !copyRouteId) {
			await goto(resolve('/journeys/[id]/stages/[stage]', { id: journey.id, stage: added.id }));
		}
	}

	function importStage(stage: string, file: File) {
		if (file.size > 20 * 1024 * 1024) {
			error = m.import_too_big();
			return Promise.resolve();
		}
		return mutate(
			() => {
				// Replace only a route that was there when the user confirmed.
				const replace = !!journey.stage_list.find((s) => s.id === stage)?.route;
				const fd = new FormData();
				fd.append('file', file);
				if (replace) fd.append('replace', 'true');
				return api().POST('/journeys/{id}/stages/{stage}/import', {
					...path(stage),
					body: { file: '' },
					bodySerializer: () => fd
				});
			},
			(r) =>
				r.status === 429
					? m.import_rate()
					: r.status === 422
						? m.stage_import_failed()
						: m.error_generic()
		);
	}

	async function move(stage: string, delta: number) {
		await mutate(() => {
			// The order as it is once earlier changes are through; the stage
			// is found by id, as those may have moved it.
			const ids = journey.stage_list.map((s) => s.id);
			const i = ids.indexOf(stage);
			if (i < 0 || !ids[i + delta]) return undefined;
			[ids[i], ids[i + delta]] = [ids[i + delta], ids[i]];
			return api().PUT('/journeys/{id}/stages/order', {
				params: { path: { id: journey.id } },
				body: { stage_ids: ids }
			});
		});
	}

	async function removeStage(stage: string) {
		await mutate(() => api().DELETE('/journeys/{id}/stages/{stage}', path(stage)));
	}

	async function removeJourney() {
		const { response } = await api().DELETE('/journeys/{id}', {
			params: { path: { id: journey.id } }
		});
		if (response.ok) await goto(resolve('/journeys'));
	}

	async function setVisibility(visibility: 'private' | 'unlisted' | 'public') {
		await mutate(() =>
			api().PATCH('/journeys/{id}', {
				params: { path: { id: journey.id }, header: { 'If-Match': `"${journey.version}"` } },
				body: { visibility }
			})
		);
	}

	function setTags(tags: string[]) {
		return mutate(() =>
			api().PATCH('/journeys/{id}', {
				params: { path: { id: journey.id }, header: { 'If-Match': `"${journey.version}"` } },
				body: { tags }
			})
		);
	}

	async function loadMyRoutes() {
		if (myRoutes.length > 0) return;
		const { data } = await api().GET('/routes');
		myRoutes = data?.routes ?? [];
	}
</script>

<Seo
	title={journey.title}
	description={`${m.seo_journey_description({
		stages: journey.stage_list.length,
		stats: [
			formatDistance(journey.totals.distance_m),
			formatDuration(journey.totals.duration_s),
			`↑\u00a0${formatHeight(journey.totals.ascent_m)}`,
			formatSAC(journey.totals.sac_grade, journey.totals.sac_max)
		].join(' · ')
	})} ${journey.description ?? ''}`}
	image={journey.stage_list.some((s) => s.route)
		? `${page.url.origin}/api/v1/journeys/${journey.id}/og.png?v=${journey.version}${token ? `&t=${token}` : ''}`
		: undefined}
	index={journey.visibility === 'public'}
/>

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<Map bind:base bind:overlays {onready} />
		<LayerSwitcher bind:base bind:overlays />
		{#if map && lib}
			<JourneyLayers {map} {lib} {journey} {hover} />
			<TravelLayers {map} {lib} trips={travelTrips} />
			<PhotoPins {map} {lib} {gallery} />
		{/if}
		{#if profile.coordinates.length > 1}
			<ProfileDock>
				<ElevationProfile
					line={profile}
					colors={STAGE_RUN_COLORS}
					breaks={journey.profile.breaks}
					bind:hover={hoverIndex}
				/>
			</ProfileDock>
		{/if}
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-96 md:flex-none md:border-t-0 md:border-l"
		data-testid="journey-panel"
	>
		<div>
			<h1 class="text-xl font-semibold" data-testid="journey-title">{journey.title}</h1>
			<p class="text-sm text-stone-500">
				{#if journey.role === 'editor'}
					{m.shared_editor_note({ user: journey.owner_username })}
				{:else if journey.visibility === 'public'}
					<a
						href={resolve('/u/[username]', { username: journey.owner_username })}
						class="hover:underline">{m.route_by({ user: journey.owner_username })}</a
					>
				{:else}
					{m.route_by({ user: journey.owner_username })}
				{/if}
			</p>
			<div class="mt-2">
				{#if canEdit}
					<TagInput tags={journey.tags} onchange={setTags} />
				{:else}
					<TagChips tags={journey.tags} />
				{/if}
			</div>
		</div>

		<div>
			<div class="mb-1 flex justify-between text-xs text-stone-500">
				<span>{m.journey_progress()}</span>
				<span data-testid="journey-progress">
					{m.journey_stages_count({
						done: journey.progress.stages_done,
						total: journey.progress.stages_total
					})}
				</span>
			</div>
			<div class="h-2 overflow-hidden rounded-full bg-stone-100">
				<div
					class="h-full bg-accent"
					style:width="{journey.progress.distance_total_m > 0
						? (journey.progress.distance_done_m / journey.progress.distance_total_m) * 100
						: 0}%"
				></div>
			</div>
		</div>

		{#if journey.totals.distance_m > 0}
			<StatsPanel {totals} pace={user?.speed_factor ?? 1} />
			<JourneyWeather id={journey.id} {token} key={routeKey + plannedDays.join()} />
			<Notices {notices} days={plannedDays} />
			<ProtectedAreas {areas} failed={areasFailed} days={plannedDays} />
		{/if}

		{#if user}
			<JourneyPeople id={journey.id} stages={journey.stage_list} {isOwner} {canEdit} bind:people />
			<JourneyReminders id={journey.id} key={plannedDays.join()} />
			<Travel
				kind="journeys"
				id={journey.id}
				{token}
				ends={journeyEnds(journey, { start: m.travel_start(), end: m.travel_end() })}
				onshow={(t) => (travelTrips = t)}
			/>
		{/if}

		{#if error}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{error}</p>{/if}

		{#key conflicts}
			<ol class="flex flex-col gap-2" data-testid="stage-list">
				{#each journey.stage_list as s, i (s.id)}
					{#if s.gap && s.gap.status !== 'ok'}
						<li
							class="rounded-md px-2 py-1 text-xs {s.gap.status === 'transfer'
								? 'bg-sky-50 text-sky-900 dark:bg-sky-950/40 dark:text-sky-200'
								: 'bg-amber-50 text-amber-900 dark:bg-amber-950/40 dark:text-amber-200'}"
							data-testid="gap"
							data-status={s.gap.status}
						>
							{m.gap_warning({ distance: formatDistance(s.gap.metres) })}
							{#if canEdit}
								<label class="mt-1 flex items-center gap-1">
									{m.gap_transfer()}
									<select
										class="rounded border border-stone-300 px-1 py-0.5"
										value={s.transfer_before ?? ''}
										onchange={(e) =>
											patchStage(s.id, {
												transfer_before: e.currentTarget.value as StagePatch['transfer_before']
											})}
									>
										<option value="">{m.transfer_none()}</option>
										<option value="pt">{m.transfer_pt()}</option>
										<option value="cablecar">{m.transfer_cablecar()}</option>
										<option value="other">{m.transfer_other()}</option>
									</select>
								</label>
							{/if}
							{#if transferUrl(i)}
								<!-- External timetable link: resolve() does not apply. -->
								<!-- eslint-disable svelte/no-navigation-without-resolve -->
								<a
									href={transferUrl(i)}
									target="_blank"
									rel="noopener noreferrer"
									class="mt-1 block underline"
									data-testid="sbb-transfer">{m.sbb_transfer()} ↗</a
								>
								<!-- eslint-enable svelte/no-navigation-without-resolve -->
							{/if}
							{#if user}
								{@const stops = transferStops(journey, i)}
								{#if stops?.from.ref && stops.to.ref}
									<button
										type="button"
										class="mt-1 underline"
										disabled={!hydrated.value}
										onclick={() => (showConnections = showConnections === s.id ? undefined : s.id)}
									>
										{showConnections === s.id ? m.connections_hide() : m.connections_show()}
									</button>
									{#if showConnections === s.id}
										<Connections from={stops.from} to={stops.to} date={s.planned_date} />
									{/if}
								{/if}
							{/if}
						</li>
					{/if}
					<StageCard
						journeyId={journey.id}
						stage={s}
						index={i}
						count={journey.stage_list.length}
						{canEdit}
						pace={user?.speed_factor ?? 1}
						{q}
						onpatch={(body) => patchStage(s.id, body)}
						onmove={(delta) => move(s.id, delta)}
						onremove={() => removeStage(s.id)}
						onimport={(file) => importStage(s.id, file)}
						people={stagePeople(people, s.id)}
					/>
				{/each}
			</ol>
		{/key}

		{#if canEdit}
			<div class="flex flex-col gap-2 text-sm">
				<button
					type="button"
					class="rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover"
					onclick={() => addStage()}
				>
					{m.journey_add_stage()}
				</button>
				<select
					class="rounded-md border border-stone-300 px-2 py-1.5"
					onfocus={loadMyRoutes}
					use:choose={(id, select) => {
						select.value = '';
						if (id) addStage(id);
					}}
					aria-label={m.journey_add_from_route()}
				>
					<option value="">{m.journey_add_from_route()}</option>
					{#each myRoutes as r (r.id)}
						<option value={r.id}>{r.title} · {formatDistance(r.totals.distance_m)}</option>
					{/each}
				</select>
			</div>
		{/if}

		{#if isOwner}
			<section class="flex flex-col gap-2 rounded-md border border-stone-200 p-3 text-sm">
				<h2 class="font-medium">{m.journey_settings()}</h2>
				<label class="flex flex-col gap-1">
					<span>{m.field_visibility()}</span>
					<select
						class="rounded-md border border-stone-300 px-2 py-1.5"
						value={journey.visibility}
						use:choose={(v) => setVisibility(v as 'private' | 'unlisted' | 'public')}
					>
						<option value="private">{m.visibility_private()}</option>
						<option value="unlisted" disabled={!user?.email_verified}
							>{m.visibility_unlisted()}</option
						>
						<option value="public" disabled={!user?.email_verified}>{m.visibility_public()}</option>
					</select>
				</label>
				{#if shareUrl && journey.visibility === 'unlisted'}
					<input
						readonly
						value={shareUrl}
						class="rounded border border-stone-300 px-1.5 py-1 text-xs"
						data-testid="journey-share-link"
					/>
				{/if}
				{#if confirming}
					<button
						type="button"
						class="self-start rounded bg-red-700 px-2 py-1 text-white"
						onclick={removeJourney}
					>
						{m.journey_delete_confirm()}
					</button>
				{:else}
					<button
						type="button"
						class="self-start text-stone-500 underline"
						onclick={() => (confirming = true)}
					>
						{m.journey_delete()}
					</button>
				{/if}
			</section>
			<SharePanel kind="journeys" id={journey.id} verified={!!user?.email_verified} />
		{/if}

		{#if user}
			<AddToCollection kind="journey" id={journey.id} />
		{/if}

		{#if journey.stage_list.some((s) => s.route)}
			<!-- API download, not a page: resolve() does not apply. -->
			<!-- eslint-disable svelte/no-navigation-without-resolve -->
			<a
				href="/api/v1/journeys/{journey.id}/gpx{q}"
				download
				class="text-sm text-accent-ink underline">{m.journey_gpx()}</a
			>
			<!-- eslint-enable svelte/no-navigation-without-resolve -->
		{/if}
		<OpenInApp kind="journeys" id={journey.id} />

		<Photos {gallery} loggedIn={!!user} />
		<Social kind="journeys" id={journey.id} {token} {user} />
	</aside>
</main>
