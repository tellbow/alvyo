<script lang="ts">
	import type { Achievements } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatHeight } from '#lib/planner/route.js';

	let { achievements: a }: { achievements: Achievements } = $props();

	const FIRST = 5;
	const kinds = {
		national: m.hiked_official_national,
		regional: m.hiked_official_regional,
		local: m.hiked_official_local,
		handicap: m.hiked_official_handicap
	};
	const names = (list: string[]) =>
		list.length > FIRST
			? `${list.slice(0, FIRST).join(', ')} ${m.hiked_more({ count: list.length - FIRST })}`
			: list.join(', ');
	const summits = $derived(
		a.summits.map((s) => (s.ele ? `${s.name} (${formatHeight(s.ele)})` : s.name))
	);
</script>

<section class="flex flex-col gap-3 text-sm" data-testid="achievements">
	<h2 class="text-base font-semibold">{m.hiked_achievements()}</h2>
	<div>
		<h3 class="font-medium">
			{m.hiked_cantons()}: {m.hiked_of({ done: a.cantons.length, total: a.cantons_total })}
		</h3>
		{#if a.cantons.length}
			<ul class="mt-1 flex flex-wrap gap-1" data-testid="achievement-cantons">
				{#each a.cantons as code (code)}
					<li class="rounded bg-stone-100 px-1.5 py-0.5 text-xs font-medium">{code}</li>
				{/each}
			</ul>
		{/if}
	</div>
	{#if a.official.length}
		<div>
			<h3 class="font-medium">{m.hiked_official()}</h3>
			<ul class="mt-1 text-stone-600">
				{#each a.official as o (o.kind)}
					<li>{kinds[o.kind]()}: {m.hiked_of({ done: o.done, total: o.total })}</li>
				{/each}
			</ul>
		</div>
	{/if}
	<div>
		<h3 class="font-medium">{m.hiked_summits()}: {a.summits.length}</h3>
		{#if summits.length}<p class="text-stone-600">{names(summits)}</p>{/if}
	</div>
	<div>
		<h3 class="font-medium">{m.hiked_huts()}: {a.huts.length}</h3>
		{#if a.huts.length}<p class="text-stone-600">{names(a.huts)}</p>{/if}
	</div>
</section>
