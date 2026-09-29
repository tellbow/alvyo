<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance } from '$lib/planner/route';
	import PoiIcon from './PoiIcon.svelte';
	import { poiText, type Poi } from './places';

	// What lies along a saved route (summits, water, fire places …), in order;
	// the first ten unless `showAll`.
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
	const FIRST = 10;

	onMount(async () => {
		const { data } = await api().GET('/routes/{id}/pois', {
			params: { path: { id }, query: token ? { t: token } : {} }
		});
		pois = data?.pois;
		if (pois) onload?.(pois);
	});
</script>

{#if pois && pois.length > 0}
	<section class="flex flex-col gap-1 text-sm" data-testid="pois">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.pois_title()}</h3>
		<ol class="flex flex-col gap-0.5">
			{#each all ? pois : pois.slice(0, FIRST) as p, i (i)}
				{@const [title, detail] = poiText(p)}
				<li class="flex gap-2" data-testid="poi">
					<span class="w-14 shrink-0 text-right text-stone-500 tabular-nums"
						>{formatDistance(p.along_m)}</span
					>
					<PoiIcon kind={p.kind} />
					<span
						>{title}{#if detail}<span class="text-stone-500">{` · ${detail}`}</span>{/if}</span
					>
				</li>
			{/each}
		</ol>
		{#if !all && pois.length > FIRST}
			<button type="button" class="self-start text-xs underline" onclick={() => (more = true)}
				>{m.pois_all({ count: pois.length })}</button
			>
		{/if}
		<p class="text-xs text-stone-500">{m.pois_source()}</p>
	</section>
{/if}
