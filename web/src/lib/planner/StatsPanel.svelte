<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import BreakdownBar from './BreakdownBar.svelte';
	import { SAC_COLOR, SURFACE_COLOR, TRAIL_COLOR, WAY_COLOR } from './colors';
	import { formatDistance, formatDuration, formatSAC, type Totals } from './route';

	let {
		totals,
		unofficialM = 0,
		pace = 1
	}: { totals: Totals; unofficialM?: number; pace?: number } = $props();

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

<dl class="grid grid-cols-2 gap-x-4 gap-y-3" data-testid="route-stats">
	<div>
		<dt class="text-xs text-stone-500">{m.stat_time()}</dt>
		<dd class="text-xl font-semibold tabular-nums" data-testid="stat-time">
			{formatDuration(totals.durationS, pace)}
		</dd>
		<dd class="text-xs text-stone-500">
			{m.stat_time_reverse({ time: formatDuration(totals.durationReverseS, pace) })}
		</dd>
	</div>
	<div>
		<dt class="text-xs text-stone-500">{m.stat_distance()}</dt>
		<dd class="text-xl font-semibold tabular-nums" data-testid="stat-distance">
			{formatDistance(totals.distanceM)}
		</dd>
	</div>
	<div>
		<dt class="text-xs text-stone-500">{m.stat_ascent()} / {m.stat_descent()}</dt>
		<dd class="font-semibold whitespace-nowrap tabular-nums">
			↑ {Math.round(totals.ascentM)} m ↓ {Math.round(totals.descentM)} m
		</dd>
	</div>
	<div>
		<dt class="text-xs text-stone-500">{m.stat_sac()}</dt>
		<dd>
			<span
				class="rounded px-1.5 py-0.5 text-sm font-semibold text-white"
				style:background={SAC_COLOR[`T${totals.sacGrade}`] ?? '#a8a29e'}
				data-testid="stat-sac"
			>
				{formatSAC(totals.sacGrade, totals.sacMax)}
			</span>
		</dd>
	</div>
</dl>
{#if unofficialM > 50}
	<p class="mt-2 text-xs text-amber-800">
		{m.stat_unofficial({ distance: formatDistance(unofficialM) })}
	</p>
{/if}

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
/>
<BreakdownBar
	title={m.breakdown_way()}
	values={totals.wayTypes}
	colors={WAY_COLOR}
	labels={wayLabels}
/>
