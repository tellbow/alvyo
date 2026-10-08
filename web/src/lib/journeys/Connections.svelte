<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Place } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';

	type Trip = components['schemas']['TransitTrip'];

	let {
		from,
		to,
		date
	}: {
		from: Place;
		to: Place;
		/** YYYY-MM-DD; today if not planned */
		date: string | null;
	} = $props();

	const clock = new Intl.DateTimeFormat('de-CH', {
		hour: '2-digit',
		minute: '2-digit',
		timeZone: 'Europe/Zurich'
	});
	const today = () =>
		new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Zurich' }).format(new Date());

	let time = $state('08:00');
	let arrive = $state(false);
	let trips = $state<Trip[]>();
	let problem = $state<'none' | 'unavailable' | 'busy'>();
	let busy = $state(false);

	async function search(e?: SubmitEvent) {
		e?.preventDefault();
		busy = true;
		problem = undefined;
		const { data, response } = await api().GET('/connections', {
			params: {
				query: { from: from.ref!, to: to.ref!, date: date ?? today(), time, arrive }
			}
		});
		busy = false;
		trips = data?.trips;
		if (data && data.trips.length === 0) problem = 'none';
		else if (response.status === 429) problem = 'busy';
		else if (!data) problem = 'unavailable';
	}

	const hhmm = (iso: string) => clock.format(new Date(iso));
	const minutes = (a: string, b: string) =>
		Math.round((new Date(b).getTime() - new Date(a).getTime()) / 60000);

	onMount(() => void search());
</script>

<div class="mt-2 flex flex-col gap-2 text-xs text-stone-800" data-testid="connections">
	<form method="post" onsubmit={search} class="flex flex-wrap items-center gap-1">
		<select
			bind:value={arrive}
			class="rounded-md border border-stone-400 px-1 py-0.5"
			aria-label={m.connections_mode()}
		>
			<option value={false}>{m.connections_depart()}</option>
			<option value={true}>{m.connections_arrive()}</option>
		</select>
		<input
			type="time"
			bind:value={time}
			class="rounded-md border border-stone-400 px-1 py-0.5"
			aria-label={m.connections_time()}
		/>
		<button class="rounded px-2 py-0.5 ring-1 ring-stone-300" disabled={busy}
			>{m.connections_search()}</button
		>
	</form>
	{#if busy}
		<p class="text-stone-500">…</p>
	{:else if problem}
		<p class="text-stone-600">
			{problem === 'none'
				? m.connections_none()
				: problem === 'busy'
					? m.share_rate()
					: m.connections_unavailable()}
		</p>
	{:else if trips}
		<ol class="flex flex-col gap-1.5">
			{#each trips as trip, i (i)}
				<li class="rounded bg-surface/70 px-1.5 py-1" data-testid="trip">
					<p class="font-medium tabular-nums">
						{hhmm(trip.start)} → {hhmm(trip.end)}
						<span class="font-normal text-stone-600">
							· {minutes(trip.start, trip.end)} min · {m.connections_transfers({
								n: trip.transfers
							})}
						</span>
					</p>
					<ul class="text-stone-600">
						{#each trip.legs as leg, i (i)}
							<li>
								{#if leg.kind === 'ride' && leg.departure && leg.arrival}
									<span class="tabular-nums">{hhmm(leg.departure)}</span>
									<span class="font-medium text-stone-800">{leg.line}</span>
									{leg.from} → {leg.to}{#if leg.platform}
										· {m.connections_platform({ p: leg.platform })}{/if}{#if leg.delay_min}
										<span class="text-red-700 dark:text-red-400"> +{leg.delay_min}′</span>{/if}
								{:else}
									{m.connections_walk({ min: leg.duration_min ?? 0 })}
								{/if}
							</li>
						{/each}
					</ul>
				</li>
			{/each}
		</ol>
		<p class="text-stone-500">{m.connections_source()}</p>
	{/if}
</div>
