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

<!-- One strip of the four numbers, the value above its name; the way back
     in the time's tooltip (on paper below it). -->
<dl
	class="grid grid-cols-[repeat(4,auto)] justify-between gap-x-2 rounded-xl bg-stone-100 px-3 py-2.5 text-center"
	data-testid="route-stats"
>
	<div
		class="flex flex-col"
		title={m.stat_time_reverse({ time: formatDuration(totals.durationReverseS, pace) })}
	>
		<dt class="text-xs text-stone-500">{m.stat_time()}</dt>
		<dd class="order-first font-semibold whitespace-nowrap tabular-nums" data-testid="stat-time">
			{formatDuration(totals.durationS, pace)}
		</dd>
		<!-- For screen readers too, not only in the tooltip. -->
		<dd class="sr-only text-xs text-stone-500 print:not-sr-only">
			{m.stat_time_reverse({ time: formatDuration(totals.durationReverseS, pace) })}
		</dd>
	</div>
	<div class="flex flex-col">
		<dt class="text-xs text-stone-500">{m.stat_distance()}</dt>
		<dd
			class="order-first font-semibold whitespace-nowrap tabular-nums"
			data-testid="stat-distance"
		>
			{formatDistance(totals.distanceM)}
		</dd>
	</div>
	<div
		class="flex flex-col"
		title="{m.stat_ascent()} {formatHeight(totals.ascentM)} · {m.stat_descent()} {formatHeight(
			totals.descentM
		)}"
	>
		<dt class="text-xs text-stone-500">{m.stat_heights()}</dt>
		<dd class="order-first text-sm leading-6 font-semibold whitespace-nowrap tabular-nums">
			<span aria-hidden="true">↑{Math.round(totals.ascentM)} ↓{Math.round(totals.descentM)}</span>
			<span class="sr-only"
				>{m.stat_ascent()}
				{formatHeight(totals.ascentM)}, {m.stat_descent()}
				{formatHeight(totals.descentM)}</span
			>
		</dd>
	</div>
	<div class="flex flex-col">
		<dt class="text-xs text-stone-500">{m.stat_sac()}</dt>
		<dd class="order-first leading-6">
			<span
				class="rounded px-1.5 py-0.5 text-sm font-semibold whitespace-nowrap"
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
