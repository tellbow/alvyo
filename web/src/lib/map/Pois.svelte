<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance, formatRange } from '$lib/planner/route';
	import PoiIcon from './PoiIcon.svelte';
	import { groupPois, poiLabel, poiText, type Poi } from './places';

	// What lies along a saved route (summits, water, fire places …), in order,
	// a town's fountains and restaurants each on one line; the first ten lines
	// unless `showAll`.
	let {
		id,
		token,
		showAll = false,
		onload
	}: {
		id: string;
		token?: string;
		showAll?: boolean;
		/** Given the points once loaded, e.g. for the map. */
		onload?: (pois: Poi[]) => void;
	} = $props();
	let pois = $state<Poi[]>();
	let more = $state(false);
	const all = $derived(showAll || more);
	const rows = $derived(pois ? groupPois(pois) : []);
	const FIRST = 10;

	onMount(async () => {
		const { data } = await api().GET('/routes/{id}/pois', {
			params: { path: { id }, query: token ? { t: token } : {} }
		});
		pois = data?.pois;
		if (pois) onload?.(pois);
	});
</script>

{#if rows.length > 0}
	{@const ranges = rows.some((r) => r.count > 1)}
	<section class="flex flex-col gap-1 text-sm" data-testid="pois">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.pois_title()}</h3>
		<!-- On paper in three columns: the sheet fits one page. -->
		<ol class="flex flex-col gap-0.5 print:block print:columns-3 print:gap-4 print:text-[10px]">
			{#each all ? rows : rows.slice(0, FIRST) as p, i (i)}
				{@const [title, detail] =
					p.count > 1 ? [`${poiLabel(p.kind)} ×${p.count}`, ''] : poiText(p)}
				<li class="flex break-inside-avoid gap-2" data-testid="poi">
					<span
						class="{ranges
							? 'w-20'
							: 'w-14'} shrink-0 text-right whitespace-nowrap text-stone-500 tabular-nums"
						>{p.count > 1 ? formatRange(p.along_m, p.to_m) : formatDistance(p.along_m)}</span
					>
					<PoiIcon kind={p.kind} />
					<span class="min-w-0"
						>{title}{#if detail}<span class="text-stone-500">{` · ${detail}`}</span>{/if}</span
					>
				</li>
			{/each}
		</ol>
		{#if !all && rows.length > FIRST}
			<button type="button" class="self-start text-xs underline" onclick={() => (more = true)}
				>{m.pois_all({ count: rows.length })}</button
			>
		{/if}
		<p class="text-xs text-stone-500">{m.pois_source()}</p>
	</section>
{/if}
