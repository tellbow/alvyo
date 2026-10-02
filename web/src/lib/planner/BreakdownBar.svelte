<script lang="ts">
	import { intlLocale } from '$lib/util/locale';
	import { m } from '$lib/paraglide/messages';
	import { legendParts, type breakdownParts } from './breakdown';
	import { formatDistance } from './route';

	let {
		title,
		parts,
		colors,
		labels
	}: {
		title: string;
		parts: ReturnType<typeof breakdownParts>;
		colors: Record<string, string>;
		labels: Record<string, () => string>;
	} = $props();

	// The three largest as shares; the metres are in the tooltips and the details.
	const legend = $derived(legendParts(parts));
	const percent = $derived(new Intl.NumberFormat(intlLocale(), { style: 'percent' }));
	const share = (s: number) => (s < 0.005 ? `<${percent.format(0.01)}` : percent.format(s));
</script>

{#if parts.length > 0}
	<section class="mt-3 first:mt-0 print:mt-2">
		<h4 class="mb-1 text-xs text-stone-500">{title}</h4>
		<!-- One kind alone is no distribution: the legend says it. -->
		{#if parts.length > 1}
			<div class="flex h-2 overflow-hidden rounded-full bg-stone-100">
				{#each parts as p (p.key)}
					<div style:width="{p.share * 100}%" style:background={colors[p.key]}></div>
				{/each}
			</div>
		{/if}
		<ul class="mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-stone-600">
			{#each legend.top as p (p.key)}
				<li class="flex items-center gap-1.5" title={formatDistance(p.metres)}>
					<span class="inline-block size-2 shrink-0 rounded-full" style:background={colors[p.key]}
					></span>
					{labels[p.key]?.() ?? p.key}
					<span class="font-semibold text-stone-900 tabular-nums">{share(p.share)}</span>
				</li>
			{/each}
			{#if legend.other > 0}
				<li class="flex items-center gap-1.5">
					{m.breakdown_other()}
					<span class="font-semibold text-stone-900 tabular-nums">{share(legend.other)}</span>
				</li>
			{/if}
		</ul>
	</section>
{/if}
