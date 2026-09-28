<script lang="ts">
	import { api, type Trip } from '$lib/api/client';
	import type { paths } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';

	type Query = NonNullable<paths['/connections']['get']['parameters']['query']>;

	// The first connections of a way by public transport, for the sheet.
	let { title, query }: { title: string; query: Query } = $props();

	const SHOWN = 3;
	const clock = new Intl.DateTimeFormat('de-CH', {
		hour: '2-digit',
		minute: '2-digit',
		timeZone: 'Europe/Zurich'
	});
	const hhmm = (iso: string) => clock.format(new Date(iso));

	let trips = $state<Trip[]>();
	let failed = $state(false);
	$effect(() => {
		const q = { ...query, lines: false };
		let stale = false;
		api()
			.GET('/connections', { params: { query: q } })
			.then(({ data }) => {
				if (stale) return;
				// Arriving by a time: the latest that fits first.
				trips = (q.arrive ? data?.trips.toReversed() : data?.trips)?.slice(0, SHOWN);
				failed = !data;
			});
		return () => {
			stale = true;
		};
	});
</script>

<div class="break-inside-avoid" data-testid="sheet-trips">
	<p class="font-medium">{title}</p>
	{#if failed}
		<p class="text-stone-600">{m.connections_unavailable()}</p>
	{:else if trips?.length === 0}
		<p class="text-stone-600">{m.connections_none()}</p>
	{:else if trips}
		<ol class="flex flex-col gap-1">
			{#each trips as trip, i (i)}
				<li data-testid="sheet-trip">
					<span class="font-medium tabular-nums">{hhmm(trip.start)} → {hhmm(trip.end)}</span>
					<span class="text-stone-600">
						· {m.connections_transfers({ n: trip.transfers })}:
						{trip.legs
							.map((l) =>
								l.kind === 'ride' && l.departure
									? `${hhmm(l.departure)} ${l.line} ${l.from} → ${l.to}${l.platform ? ` (${m.connections_platform({ p: l.platform })})` : ''}`
									: m.connections_walk({ min: l.duration_min ?? 0 })
							)
							.join(', ')}
					</span>
				</li>
			{/each}
		</ol>
	{/if}
</div>
