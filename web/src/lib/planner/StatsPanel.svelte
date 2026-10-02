<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import Breakdowns from './Breakdowns.svelte';
	import { sacBackground, sacInk } from './colors';
	import { formatDistance, formatHeight, formatDuration, formatSAC, type Totals } from './route';

	let {
		totals,
		unofficialM = 0,
		pace = 1,
		breakdown = true
	}: {
		totals: Totals;
		unofficialM?: number;
		pace?: number;
		/** the bars of trails, surfaces and ways below; else placed apart */
		breakdown?: boolean;
	} = $props();
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
			↑&nbsp;{formatHeight(totals.ascentM)} ↓&nbsp;{formatHeight(totals.descentM)}
		</dd>
	</div>
	<div>
		<dt class="text-xs text-stone-500">{m.stat_sac()}</dt>
		<dd>
			<span
				class="rounded px-1.5 py-0.5 text-sm font-semibold"
				style:background={sacBackground(totals.sacGrade)}
				style:color={sacInk(totals.sacGrade)}
				data-testid="stat-sac"
			>
				{formatSAC(totals.sacGrade, totals.sacMax)}
			</span>
		</dd>
	</div>
</dl>
{#if unofficialM > 50}
	<p class="mt-2 text-xs text-amber-800 dark:text-amber-200">
		{m.stat_unofficial({ distance: formatDistance(unofficialM) })}
	</p>
{/if}

{#if breakdown}<Breakdowns {totals} />{/if}
