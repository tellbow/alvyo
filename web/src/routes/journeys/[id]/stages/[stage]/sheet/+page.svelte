<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { api, type Home, type Travel } from '#lib/api/client.js';
	import { placeDetail } from '#lib/journeys/places.js';
	import { transferStops } from '#lib/journeys/transfer.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import Sheet from '#lib/sheet/Sheet.svelte';
	import SheetTrips from '#lib/sheet/SheetTrips.svelte';
	import { chosenWays, journeyEnds, swissToday } from '#lib/travel/travel.js';

	let { data } = $props();
	const journey = $derived(data.journey);
	const stage = $derived(journey.stage_list[data.index]);
	// svelte-ignore state_referenced_locally
	let date = $state(data.journey.stage_list[data.index].planned_date ?? swissToday());
	const q = $derived(data.token ? `?t=${data.token}` : '');

	const placesTitle = $derived(
		stage.start_place && stage.end_place
			? `${stage.start_place.name} – ${stage.end_place.name}`
			: ''
	);
	const routed = $derived(journey.stage_list.filter((s) => s.route));
	const transfer = $derived(transferStops(journey, data.index));

	// The way from home (or elsewhere) before the first stage and back after
	// the last, as the person chose it for the journey.
	let homes = $state<Home[]>([]);
	let travel = $state<Travel>({});
	onMount(async () => {
		if (!data.user || (routed[0] !== stage && routed.at(-1) !== stage)) return;
		const [h, t] = await Promise.all([
			api().GET('/me/homes'),
			api().GET('/journeys/{id}/travel', {
				params: { path: { id: journey.id }, query: data.token ? { t: data.token } : {} }
			})
		]);
		homes = h.data?.homes ?? [];
		travel = t.data ?? {};
	});
	const ends = $derived(journeyEnds(journey, { start: m.travel_start(), end: m.travel_end() }));
	const ways = $derived(
		chosenWays(travel, homes, ends, date).filter((w) =>
			w.direction === 'to' ? routed[0] === stage : routed.at(-1) === stage
		)
	);
</script>

<Seo title={journey.title} index={false} />

{#snippet places()}
	<section class="flex flex-col gap-1" data-testid="sheet-places">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.sheet_places()}</h3>
		<dl class="grid grid-cols-[auto_1fr] gap-x-2 gap-y-1">
			{#each [[m.place_start(), stage.start_place], [m.place_end(), stage.end_place]] as const as [label, p] (label)}
				{#if p}
					<dt class="text-stone-500">{label}</dt>
					<dd>
						<span class="font-medium">{p.name}</span>
						<span class="text-stone-500">· {placeDetail(p)}</span>
					</dd>
				{/if}
			{/each}
			{#if stage.accommodation}
				<dt class="text-stone-500">{m.stage_accommodation()}</dt>
				<dd>
					{stage.accommodation}{#if stage.accommodation_booked}
						({m.stage_booked()}){/if}
				</dd>
			{/if}
		</dl>
		{#if stage.notes}<p class="whitespace-pre-line text-stone-600">{stage.notes}</p>{/if}
	</section>
{/snippet}

{#snippet connections()}
	{#if transfer || ways.length > 0}
		<section class="flex flex-col gap-2" data-testid="sheet-connections">
			<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
				{m.sheet_connections()}
			</h3>
			{#each ways.filter((w) => w.direction === 'to') as w (w.direction)}
				<SheetTrips title="{m.travel_to()}: {w.from} → {w.to}" query={w.query} />
			{/each}
			{#if transfer}
				<SheetTrips
					title="{transfer.from.name} → {transfer.to.name}"
					query={{
						from: transfer.from.ref!,
						to: transfer.to.ref!,
						date,
						time: '08:00',
						arrive: false
					}}
				/>
			{/if}
			{#each ways.filter((w) => w.direction === 'back') as w (w.direction)}
				<SheetTrips title="{m.travel_back()}: {w.from} → {w.to}" query={w.query} />
			{/each}
		</section>
	{/if}
{/snippet}

<Sheet
	route={data.route}
	token={data.token}
	user={data.user}
	heading={stage.title || placesTitle || m.journey_stage({ n: data.index + 1 })}
	subtitle="{m.journey_stage({ n: data.index + 1 })} · {journey.title}"
	back="{resolve('/journeys/[id]', { id: journey.id })}{q}"
	bind:date
	{places}
	{connections}
/>
