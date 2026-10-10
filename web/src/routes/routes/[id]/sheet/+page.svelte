<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { api, type Home, type Travel } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import Sheet from '#lib/sheet/Sheet.svelte';
	import SheetTrips from '#lib/sheet/SheetTrips.svelte';
	import { chosenWays, routeEnds, swissToday } from '#lib/travel/travel.js';

	let { data } = $props();
	let date = $state(swissToday());
	const q = $derived(data.token ? `?t=${data.token}` : '');

	// The way there and back, as the person chose it for the route.
	let homes = $state<Home[]>([]);
	let travel = $state<Travel>({});
	onMount(async () => {
		if (!data.user) return;
		const [h, t] = await Promise.all([
			api().GET('/me/homes'),
			api().GET('/routes/{id}/travel', {
				params: { path: { id: data.route.id }, query: data.token ? { t: data.token } : {} }
			})
		]);
		homes = h.data?.homes ?? [];
		travel = t.data ?? {};
	});
	const ways = $derived(
		chosenWays(
			travel,
			homes,
			routeEnds(data.route, { start: m.place_start(), end: m.place_end() }),
			date
		)
	);
</script>

<Seo title={data.route.title} index={false} />

{#snippet connections()}
	{#if ways.length > 0}
		<section class="flex flex-col gap-2" data-testid="sheet-connections">
			<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
				{m.sheet_connections()}
			</h3>
			{#each ways as w (w.direction)}
				<SheetTrips
					title="{w.direction === 'to' ? m.travel_to() : m.travel_back()}: {w.from} → {w.to}"
					query={w.query}
				/>
			{/each}
		</section>
	{/if}
{/snippet}

<Sheet
	route={data.route}
	token={data.token}
	user={data.user}
	heading={data.route.title}
	back="{resolve('/routes/[id]', { id: data.route.id })}{q}"
	bind:date
	{connections}
/>
