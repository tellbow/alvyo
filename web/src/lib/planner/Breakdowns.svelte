<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import BreakdownBar from './BreakdownBar.svelte';
	import { SURFACE_COLOR, TRAIL_COLOR, WAY_COLOR } from './colors';
	import type { Totals } from './route';

	// The bars of a route's trails, surfaces and kinds of way.
	let { totals, class: className = '' }: { totals: Totals; class?: string } = $props();

	const trailLabels = {
		Wanderweg: m.trail_Wanderweg,
		Bergwanderweg: m.trail_Bergwanderweg,
		Alpinwanderweg: m.trail_Alpinwanderweg,
		none: m.trail_none
	};
	const surfaceLabels = {
		paved: m.surface_paved,
		gravel: m.surface_gravel,
		natural: m.surface_natural,
		unknown: m.surface_unknown
	};
	const wayLabels = {
		road: m.way_road,
		track: m.way_track,
		path: m.way_path,
		steps: m.way_steps,
		unknown: m.way_unknown
	};
</script>

<div class={className}>
	<BreakdownBar
		title={m.breakdown_trail()}
		values={totals.trails}
		colors={TRAIL_COLOR}
		labels={trailLabels}
	/>
	<BreakdownBar
		title={m.breakdown_surface()}
		values={totals.surfaces}
		colors={SURFACE_COLOR}
		labels={surfaceLabels}
		unknown="unknown"
	/>
	<BreakdownBar
		title={m.breakdown_way()}
		values={totals.wayTypes}
		colors={WAY_COLOR}
		labels={wayLabels}
		unknown="unknown"
	/>
</div>
