<script lang="ts">
	import { api, type Place } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance } from '$lib/planner/route';
	import { placeDetail, placeLabel } from './places';

	let {
		near,
		current,
		onpick,
		onclose
	}: {
		/** lon, lat to search around (the route start or end) */
		near: number[];
		current: Place | null;
		/** a place id, or '' for the suggestion */
		onpick: (id: string) => void;
		onclose: () => void;
	} = $props();

	type Kind = Place['kind'];
	const KINDS: Kind[] = ['pt_stop', 'hut', 'hotel', 'campsite'];

	let q = $state('');
	let kind = $state<Kind | ''>('');
	let results = $state<Place[]>();

	$effect(() => {
		const query = {
			lon: near[0],
			lat: near[1],
			q: q.trim() || undefined,
			kind: kind ? [kind] : undefined
		};
		let stale = false;
		const timer = setTimeout(
			async () => {
				const { data } = await api().GET('/places/nearby', { params: { query } });
				if (!stale) results = data?.places ?? [];
			},
			query.q ? 250 : 0
		);
		return () => {
			stale = true;
			clearTimeout(timer);
		};
	});
</script>

<div
	class="mt-2 flex flex-col gap-2 rounded-md bg-stone-50 p-2 ring-1 ring-stone-200"
	data-testid="place-picker"
>
	<div class="flex gap-2">
		<input
			class="min-w-0 flex-1 rounded-md border border-stone-400 px-2 py-1"
			placeholder={m.place_search()}
			aria-label={m.place_search()}
			bind:value={q}
		/>
		<select
			class="rounded-md border border-stone-400 px-1"
			bind:value={kind}
			aria-label={m.place_kind()}
		>
			<option value="">{m.place_kind_all()}</option>
			{#each KINDS as k (k)}
				<option value={k}>{placeLabel(k)}</option>
			{/each}
		</select>
	</div>
	{#if results?.length === 0}
		<p class="text-xs text-stone-500">{m.place_nothing_found()}</p>
	{:else if results}
		<ul class="flex max-h-56 flex-col overflow-y-auto">
			{#each results as p (p.id)}
				<li>
					<button
						type="button"
						class="flex w-full items-baseline gap-2 rounded px-1 py-0.5 text-left hover:bg-surface"
						class:font-semibold={p.id === current?.id}
						onclick={() => onpick(p.id)}
					>
						<span class="flex-1">{p.name}</span>
						<span class="text-xs text-stone-500">{placeDetail(p)}</span>
						<span class="w-14 text-right text-xs text-stone-500 tabular-nums"
							>{formatDistance(p.distance_m)}</span
						>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
	<div class="flex justify-between text-xs">
		{#if current && !current.suggested}
			<button type="button" class="text-accent-ink underline" onclick={() => onpick('')}>
				{m.place_use_suggestion()}
			</button>
		{/if}
		<button type="button" class="ml-auto text-stone-500 underline" onclick={onclose}>
			{m.place_close()}
		</button>
	</div>
</div>
