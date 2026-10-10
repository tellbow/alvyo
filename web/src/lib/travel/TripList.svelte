<script lang="ts">
	import type { Trip } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';

	let {
		trips,
		chosen,
		onchoose
	}: { trips: Trip[]; chosen: number; onchoose: (i: number) => void } = $props();

	const clock = new Intl.DateTimeFormat('de-CH', {
		hour: '2-digit',
		minute: '2-digit',
		timeZone: 'Europe/Zurich'
	});
	const hhmm = (iso: string) => clock.format(new Date(iso));
	const minutes = (a: string, b: string) =>
		Math.round((new Date(b).getTime() - new Date(a).getTime()) / 60000);
	const lines = (trip: Trip) =>
		trip.legs.flatMap((l) => (l.kind === 'ride' && l.line ? [l.line] : [])).join(' › ');

	// Three at first, the chosen one always.
	let more = $state(false);
	const shown = $derived(more ? trips : trips.slice(0, Math.max(3, chosen + 1)));
</script>

<!-- One line each; the chosen one, drawn on the map, with its legs. -->
<ol class="flex flex-col gap-1.5 text-xs text-stone-800">
	{#each shown as trip, i (i)}
		<li>
			<button
				type="button"
				class="w-full rounded-lg px-2.5 py-1.5 text-left ring-1 {i === chosen
					? 'bg-accent-soft ring-accent'
					: 'bg-surface/70 ring-stone-200 hover:ring-stone-400'}"
				aria-pressed={i === chosen}
				aria-expanded={i === chosen}
				title={m.travel_on_map()}
				onclick={() => onchoose(i)}
				data-testid="trip"
			>
				<span class="flex flex-wrap justify-between gap-x-2">
					<span class="font-semibold tabular-nums">{hhmm(trip.start)} → {hhmm(trip.end)}</span>
					<span class="text-stone-600">
						{minutes(trip.start, trip.end)} min · {m.connections_transfers({
							n: trip.transfers
						})}{#if lines(trip)}{` · ${lines(trip)}`}{/if}
					</span>
				</span>
				{#if i === chosen}
					<span class="mt-1 block text-stone-600">
						{#each trip.legs as leg, j (j)}
							<span class="block">
								{#if leg.kind === 'ride' && leg.departure}
									<span class="tabular-nums">{hhmm(leg.departure)}</span>
									<span class="font-medium text-stone-800">{leg.line}</span>
									{leg.from} → {leg.to}{#if leg.platform}
										· {m.connections_platform({ p: leg.platform })}{/if}{#if leg.delay_min}
										<span class="text-red-700 dark:text-red-400"> +{leg.delay_min}′</span>{/if}
								{:else}
									{m.connections_walk({ min: leg.duration_min ?? 0 })}
								{/if}
							</span>
						{/each}
					</span>
				{/if}
			</button>
		</li>
	{/each}
</ol>
{#if shown.length < trips.length}
	<button
		type="button"
		class="mt-1 self-start text-xs text-accent-ink hover:underline"
		onclick={() => (more = true)}>{m.connections_more()}</button
	>
{/if}
<p class="mt-1 text-xs text-stone-500">{m.connections_source()}</p>
