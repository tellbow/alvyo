<script lang="ts">
	import type { HikedTotals } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatDistance, formatDuration, formatHeight } from '#lib/planner/route.js';

	let { totals }: { totals: HikedTotals } = $props();
</script>

<dl class="grid grid-cols-2 gap-3 text-sm" data-testid="hiked-stats">
	{#each [[m.hiked_hikes(), String(totals.hikes)], [m.hiked_distance(), formatDistance(totals.distance_m)], [m.hiked_ascent(), formatHeight(totals.ascent_m)], [m.hiked_time(), formatDuration(totals.time_s)], [m.hiked_highest(), totals.highest_m > 0 ? formatHeight(totals.highest_m) : '–'], [m.hiked_longest(), formatDistance(totals.longest_m)]] as [label, value] (label)}
		<div>
			<dt class="text-stone-500">{label}</dt>
			<dd class="text-lg font-semibold">{value}</dd>
		</div>
	{/each}
</dl>
