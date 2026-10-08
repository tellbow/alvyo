<script lang="ts">
	import { choose as pick } from '$lib/util/choose';
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { api, type Home, type Travel, type TravelWay, type Trip } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import PlaceSearch from '$lib/planner/PlaceSearch.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import TripList from './TripList.svelte';
	import { swissToday, travelQuery, waySpot, type End } from './travel';

	let {
		kind,
		id,
		token,
		ends,
		onshow
	}: {
		kind: 'journeys' | 'routes';
		id: string;
		/** Share token of an unlisted journey or route. */
		token?: string;
		/** Where public transport meets the hike. */
		ends: { start?: End; end?: End };
		/** Gets the trips chosen to be drawn on the map. */
		onshow: (trips: Trip[]) => void;
	} = $props();

	type Direction = 'to' | 'back';
	const ELSEWHERE = 'elsewhere';
	const hydrated = new Hydrated();
	let homes = $state<Home[]>();
	let travel = $state<Travel>({});
	let trips = $state<Record<Direction, Trip[] | undefined>>({ to: undefined, back: undefined });
	let problem = $state<Record<Direction, string>>({ to: '', back: '' });
	let busy = $state<Record<Direction, boolean>>({ to: false, back: false });
	let chosen = $state<Record<Direction, number>>({ to: 0, back: 0 });
	/** Searching for another place than a home. */
	let searching = $state<Record<Direction, boolean>>({ to: false, back: false });
	// A route has no day of its own: the connections of the day chosen here.
	let day = $state(swissToday());

	const query = $derived(token ? { t: token } : {});
	const params = $derived({ params: { path: { id }, query } });

	$effect(() => {
		onshow(
			(['to', 'back'] as const).flatMap((d) => {
				const t = trips[d]?.[chosen[d]];
				return t ? [t] : [];
			})
		);
	});

	onMount(async () => {
		const [h, t] = await Promise.all([
			api().GET('/me/homes'),
			kind === 'routes'
				? api().GET('/routes/{id}/travel', params)
				: api().GET('/journeys/{id}/travel', params)
		]);
		homes = h.data?.homes ?? [];
		travel = t.data ?? {};
		void search('to');
		void search('back');
	});

	// The latest search and change per direction: answers to earlier ones
	// that arrive late are dropped.
	const asked: Record<Direction, number> = { to: 0, back: 0 };
	const changed: Record<Direction, number> = { to: 0, back: 0 };

	async function search(d: Direction) {
		const n = ++asked[d];
		const way = travel[d];
		const spot = waySpot(way, homes ?? []);
		const at = d === 'to' ? ends.start : ends.end;
		trips[d] = undefined;
		problem[d] = '';
		if (!way || !spot || !at) return;
		busy[d] = true;
		const { data, response } = await api().GET('/connections', {
			params: { query: travelQuery(d, spot, { ...at, date: at.date ?? day }, way) }
		});
		if (n !== asked[d]) return;
		busy[d] = false;
		// Arriving by a time: the latest that fits first.
		trips[d] = way.arrive ? data?.trips.toReversed() : data?.trips;
		chosen[d] = 0;
		if (data && data.trips.length === 0) problem[d] = m.connections_none();
		else if (response.status === 429) problem[d] = m.share_rate();
		else if (!data) problem[d] = m.connections_unavailable();
	}

	async function change(d: Direction, way: TravelWay | undefined) {
		const n = ++changed[d];
		const next = { ...travel, [d]: way };
		if (!way) delete next[d];
		const body = { ...params, body: next };
		const { data } =
			kind === 'routes'
				? await api().PUT('/routes/{id}/travel', body)
				: await api().PUT('/journeys/{id}/travel', body);
		if (data && n === changed[d]) {
			travel = data;
			void search(d);
		}
	}

	/** A home, another place, or the time; home_id '' for none. */
	function edit(d: Direction, patch: Partial<TravelWay>) {
		const now = travel[d];
		if (patch.home_id === '') return change(d, undefined);
		const where = patch.home_id
			? { home_id: patch.home_id }
			: patch.place
				? { place: patch.place }
				: now?.place
					? { place: now.place }
					: now?.home_id
						? { home_id: now.home_id }
						: undefined;
		if (!where) return;
		void change(d, {
			...where,
			time: patch.time ?? now?.time ?? (d === 'to' ? '07:00' : '17:00'),
			arrive: patch.arrive ?? now?.arrive ?? false
		});
	}

	function choose(d: Direction, value: string) {
		searching[d] = value === ELSEWHERE;
		if (value !== ELSEWHERE) void edit(d, { home_id: value });
	}

	/** A stop has only its number: the search then prefers nothing nearby. */
	function coordsOf(at: End): [number, number] | undefined {
		const [lon, lat] = at.at.split(',').map(Number);
		return at.at.includes(',') ? [lon, lat] : undefined;
	}

	function changeDay(value: string) {
		if (!value) return;
		day = value;
		void search('to');
		void search('back');
	}
</script>

<section class="flex flex-col gap-3 text-sm" data-testid="travel">
	<h2 class="font-semibold">{m.travel_title()}</h2>
	{#if homes}
		{#if homes.length === 0}
			<p class="text-stone-600">
				{m.travel_no_homes()}
				<a href={resolve('/account')} class="text-accent-ink underline">{m.travel_account()}</a>
			</p>
		{/if}
		{#if kind === 'routes'}
			<label class="flex items-center gap-1">
				{m.travel_day()}
				<input
					type="date"
					class="rounded-md border border-stone-400 px-1 py-0.5"
					value={day}
					onchange={(e) => changeDay(e.currentTarget.value)}
					data-testid="travel-day"
				/>
			</label>
		{/if}
		{#each ['to', 'back'] as const as d (d)}
			{@const way = travel[d]}
			{@const at = d === 'to' ? ends.start : ends.end}
			<div
				class="flex flex-col gap-1.5 rounded-xl border border-stone-200 p-3"
				data-testid="travel-{d}"
			>
				<p class="font-medium">
					{d === 'to' ? m.travel_to() : m.travel_back()}
					{#if at?.name}<span class="font-normal text-stone-500">
							· {d === 'to' ? '→' : '←'} {at.name}</span
						>{/if}
				</p>
				<div class="flex flex-wrap items-center gap-1">
					<label class="flex items-center gap-1">
						{d === 'to' ? m.travel_from() : m.travel_to_home()}
						<select
							class="rounded-md border border-stone-400 px-1 py-0.5"
							value={searching[d] || way?.place ? ELSEWHERE : (way?.home_id ?? '')}
							disabled={!hydrated.value}
							use:pick={(v) => choose(d, v)}
							data-testid="travel-{d}-home"
						>
							<option value="">{m.travel_none()}</option>
							{#each homes as h (h.id)}
								<option value={h.id}>{h.name}</option>
							{/each}
							<option value={ELSEWHERE}>{m.travel_elsewhere()}</option>
						</select>
					</label>
					{#if way?.place && !searching[d]}
						<span data-testid="travel-{d}-place">{way.place.name}</span>
						<button
							type="button"
							class="text-accent-ink underline"
							onclick={() => (searching[d] = true)}>{m.place_change()}</button
						>
					{/if}
					{#if way}
						<select
							class="rounded-md border border-stone-400 px-1 py-0.5"
							value={way.arrive}
							aria-label={m.connections_mode()}
							use:pick={(v) => edit(d, { arrive: v === 'true' })}
							data-testid="travel-{d}-mode"
						>
							<option value={false}>{m.connections_depart()}</option>
							<option value={true}>{m.connections_arrive()}</option>
						</select>
						<input
							type="time"
							class="rounded-md border border-stone-400 px-1 py-0.5"
							value={way.time}
							aria-label={m.connections_time()}
							onchange={(e) => e.currentTarget.value && edit(d, { time: e.currentTarget.value })}
							data-testid="travel-{d}-time"
						/>
					{/if}
				</div>
				{#if searching[d]}
					<div data-testid="travel-{d}-search">
						<PlaceSearch
							label={m.travel_place_search()}
							near={() => (at ? coordsOf(at) : undefined)}
							onpick={(p) => {
								searching[d] = false;
								void edit(d, { place: { name: p.name.slice(0, 60), lon: p.at[0], lat: p.at[1] } });
							}}
						/>
					</div>
				{/if}
				{#if way && !at}
					<p class="text-xs text-stone-500">{m.travel_no_route()}</p>
				{:else if way && at}
					<!-- A route's day is the one chosen above. -->
					{#if kind === 'journeys'}
						<p class="text-xs text-stone-500">
							{at.date
								? m.travel_on({ date: at.date.split('-').reverse().join('.') })
								: m.travel_no_date()}
						</p>
					{/if}
					{#if busy[d]}
						<p class="text-xs text-stone-500">…</p>
					{:else if problem[d]}
						<p class="text-xs text-stone-600">{problem[d]}</p>
					{:else if trips[d]}
						<TripList trips={trips[d]!} chosen={chosen[d]} onchoose={(i) => (chosen[d] = i)} />
					{/if}
				{/if}
			</div>
		{/each}
		<p class="text-xs text-stone-500">{m.travel_private()}</p>
	{/if}
</section>
