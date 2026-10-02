<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import { breakdownParts } from './breakdown';
	import BreakdownBar from './BreakdownBar.svelte';
	import { SURFACE_COLOR, TRAIL_COLOR, WAY_COLOR } from './colors';
	import { formatDistance, type Totals } from './route';

	// The bars of a route's trails, surfaces and kinds of way, the metres of
	// each behind «Details».
	let { totals, class: className = '' }: { totals: Totals; class?: string } = $props();

	type Bar = {
		title: string;
		colors: Record<string, string>;
		labels: Record<string, () => string>;
		parts: ReturnType<typeof breakdownParts>;
	};
	const bars = $derived<Bar[]>([
		{
			title: m.breakdown_trail(),
			colors: TRAIL_COLOR,
			labels: {
				Wanderweg: m.trail_Wanderweg,
				Bergwanderweg: m.trail_Bergwanderweg,
				Alpinwanderweg: m.trail_Alpinwanderweg,
				none: m.trail_none
			},
			parts: breakdownParts(totals.trails, Object.keys(TRAIL_COLOR))
		},
		{
			title: m.breakdown_surface(),
			colors: SURFACE_COLOR,
			labels: {
				paved: m.surface_paved,
				gravel: m.surface_gravel,
				natural: m.surface_natural,
				unknown: m.surface_unknown
			},
			// «Not known» alone: the bar is left out.
			parts: breakdownParts(totals.surfaces, Object.keys(SURFACE_COLOR), 'unknown')
		},
		{
			title: m.breakdown_way(),
			colors: WAY_COLOR,
			labels: {
				road: m.way_road,
				track: m.way_track,
				path: m.way_path,
				steps: m.way_steps,
				unknown: m.way_unknown
			},
			parts: breakdownParts(totals.wayTypes, Object.keys(WAY_COLOR), 'unknown')
		}
	]);
	const metres = $derived(
		bars.flatMap((b) =>
			b.parts.map((p) => `${b.labels[p.key]?.() ?? p.key} ${formatDistance(p.metres)}`)
		)
	);
</script>

<div class={className}>
	{#each bars as b (b.title)}
		<BreakdownBar title={b.title} parts={b.parts} colors={b.colors} labels={b.labels} />
	{/each}
	{#if metres.length > 0}
		<details class="mt-2 text-xs text-stone-600 print:hidden">
			<summary class="cursor-pointer text-stone-500">{m.breakdown_details()}</summary>
			<p class="mt-1">{metres.join(' · ')}</p>
		</details>
	{/if}
</div>
