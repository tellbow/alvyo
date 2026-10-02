<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance, formatRange } from '$lib/planner/route';
	import PoiIcon from './PoiIcon.svelte';
	import { groupPois, POI_KINDS, poiLabel, poiText, type Poi, type PoiKind } from './places';

	// What lies along a saved route (summits, water, fire places …), in order,
	// a town's fountains and restaurants each on one line; chips above show
	// one kind only.
	let {
		id,
		token,
		onload
	}: {
		id: string;
		token?: string;
		/** Given the points once loaded, e.g. for the map. */
		onload?: (pois: Poi[]) => void;
	} = $props();
	let pois = $state<Poi[]>();
	let only = $state<PoiKind>();
	const counts = $derived(
		POI_KINDS.map((kind) => ({ kind, n: pois?.filter((p) => p.kind === kind).length ?? 0 })).filter(
			(c) => c.n > 0
		)
	);
	const rows = $derived(pois ? groupPois(only ? pois.filter((p) => p.kind === only) : pois) : []);

	onMount(async () => {
		const { data } = await api().GET('/routes/{id}/pois', {
			params: { path: { id }, query: token ? { t: token } : {} }
		});
		pois = data?.pois;
		if (pois) onload?.(pois);
	});

	const chip = (on: boolean) =>
		`flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs ring-1 ${on ? 'bg-stone-900 text-surface ring-stone-900' : 'ring-stone-300 hover:bg-stone-100'}`;
</script>

{#if pois && pois.length > 0}
	{@const ranges = rows.some((r) => r.count > 1)}
	<section class="flex flex-col gap-1 text-sm" data-testid="pois">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.pois_title()}</h3>
		{#if counts.length > 1}
			<div
				class="mb-1 flex flex-wrap gap-1.5 print:hidden"
				role="group"
				aria-label={m.pois_title()}
			>
				<button
					type="button"
					class={chip(!only)}
					aria-pressed={!only}
					onclick={() => (only = undefined)}>{m.pois_filter_all({ count: pois.length })}</button
				>
				{#each counts as c (c.kind)}
					<button
						type="button"
						class={chip(only === c.kind)}
						aria-pressed={only === c.kind}
						onclick={() => (only = c.kind)}
						><PoiIcon kind={c.kind} size={14} />{poiLabel(c.kind)}
						<span class="tabular-nums">{c.n}</span></button
					>
				{/each}
			</div>
		{/if}
		<!-- On paper in three columns: the sheet fits one page. -->
		<ol class="flex flex-col gap-0.5 print:block print:columns-3 print:gap-4 print:text-[10px]">
			{#each rows as p, i (i)}
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
		<p class="text-xs text-stone-500">{m.pois_source()}</p>
	</section>
{/if}
