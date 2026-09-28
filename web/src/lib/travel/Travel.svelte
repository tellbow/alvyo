<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import {
		api,
		type Home,
		type Journey,
		type Travel,
		type TravelWay,
		type Trip
	} from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import TripList from './TripList.svelte';
	import { journeyEnds, travelQuery } from './travel';

	let {
		journey,
		token,
		onshow
	}: {
		journey: Journey;
		/** Share token of an unlisted journey. */
		token?: string;
		/** Gets the trips chosen to be drawn on the map. */
		onshow: (trips: Trip[]) => void;
	} = $props();

	type Direction = 'to' | 'back';
	const hydrated = new Hydrated();
	let homes = $state<Home[]>();
	let travel = $state<Travel>({});
	let trips = $state<Record<Direction, Trip[] | undefined>>({ to: undefined, back: undefined });
	let problem = $state<Record<Direction, string>>({ to: '', back: '' });
	let busy = $state<Record<Direction, boolean>>({ to: false, back: false });
	let chosen = $state<Record<Direction, number>>({ to: 0, back: 0 });

	const ends = $derived(journeyEnds(journey, { start: m.travel_start(), end: m.travel_end() }));
	const query = $derived(token ? { t: token } : {});

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
			api().GET('/journeys/{id}/travel', { params: { path: { id: journey.id }, query } })
		]);
		homes = h.data?.homes ?? [];
		travel = t.data ?? {};
		void search('to');
		void search('back');
	});

	async function search(d: Direction) {
		const way = travel[d];
		const home = homes?.find((h) => h.id === way?.home_id);
		const at = d === 'to' ? ends.start : ends.end;
		trips[d] = undefined;
		problem[d] = '';
		if (!way || !home || !at) return;
		busy[d] = true;
		const { data, response } = await api().GET('/connections', {
			params: { query: travelQuery(d, home, at, way) }
		});
		busy[d] = false;
		// Arriving by a time: the latest that fits first.
		trips[d] = way.arrive ? data?.trips.toReversed() : data?.trips;
		chosen[d] = 0;
		if (data && data.trips.length === 0) problem[d] = m.connections_none();
		else if (response.status === 429) problem[d] = m.share_rate();
		else if (!data) problem[d] = m.connections_unavailable();
	}

	async function change(d: Direction, way: TravelWay | undefined) {
		const next = { ...travel, [d]: way };
		if (!way) delete next[d];
		const { data } = await api().PUT('/journeys/{id}/travel', {
			params: { path: { id: journey.id }, query },
			body: next
		});
		if (data) {
			travel = data;
			void search(d);
		}
	}

	function edit(d: Direction, patch: Partial<TravelWay>) {
		const now = travel[d];
		if (patch.home_id === '') return change(d, undefined);
		const home = patch.home_id ?? now?.home_id;
		if (!home) return;
		void change(d, {
			home_id: home,
			time: patch.time ?? now?.time ?? (d === 'to' ? '07:00' : '17:00'),
			arrive: patch.arrive ?? now?.arrive ?? false
		});
	}
</script>

<section class="flex flex-col gap-3 text-sm" data-testid="travel">
	<h2 class="font-semibold">{m.travel_title()}</h2>
	{#if homes && homes.length === 0}
		<p class="text-stone-600">
			{m.travel_no_homes()}
			<a href={resolve('/account')} class="text-accent-ink underline">{m.travel_account()}</a>
		</p>
	{:else if homes}
		{#each ['to', 'back'] as const as d (d)}
			{@const way = travel[d]}
			{@const at = d === 'to' ? ends.start : ends.end}
			<div class="flex flex-col gap-1.5" data-testid="travel-{d}">
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
							class="rounded border border-stone-300 px-1 py-0.5"
							value={way?.home_id ?? ''}
							disabled={!hydrated.value}
							onchange={(e) => edit(d, { home_id: e.currentTarget.value })}
							data-testid="travel-{d}-home"
						>
							<option value="">{m.travel_none()}</option>
							{#each homes as h (h.id)}
								<option value={h.id}>{h.name}</option>
							{/each}
						</select>
					</label>
					{#if way}
						<select
							class="rounded border border-stone-300 px-1 py-0.5"
							value={way.arrive}
							aria-label={m.connections_mode()}
							onchange={(e) => edit(d, { arrive: e.currentTarget.value === 'true' })}
							data-testid="travel-{d}-mode"
						>
							<option value={false}>{m.connections_depart()}</option>
							<option value={true}>{m.connections_arrive()}</option>
						</select>
						<input
							type="time"
							class="rounded border border-stone-300 px-1 py-0.5"
							value={way.time}
							aria-label={m.connections_time()}
							onchange={(e) => e.currentTarget.value && edit(d, { time: e.currentTarget.value })}
							data-testid="travel-{d}-time"
						/>
					{/if}
				</div>
				{#if way && !at}
					<p class="text-xs text-stone-500">{m.travel_no_route()}</p>
				{:else if way && at}
					<p class="text-xs text-stone-500">
						{at.date
							? m.travel_on({ date: at.date.split('-').reverse().join('.') })
							: m.travel_no_date()}
					</p>
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
		<p class="text-xs text-stone-400">{m.travel_private()}</p>
	{/if}
</section>
