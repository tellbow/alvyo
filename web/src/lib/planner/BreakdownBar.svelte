<script lang="ts">
	import { formatDistance } from './route';

	let {
		title,
		values,
		colors,
		labels
	}: {
		title: string;
		values: Record<string, number>;
		colors: Record<string, string>;
		labels: Record<string, () => string>;
	} = $props();

	const total = $derived(Object.values(values).reduce((a, b) => a + b, 0));
	const parts = $derived(
		Object.keys(colors)
			.filter((k) => (values[k] ?? 0) > 0)
			.map((k) => ({ key: k, metres: values[k], share: values[k] / total }))
	);
</script>

{#if total > 0}
	<section class="mt-4">
		<h3 class="mb-1 text-xs font-medium tracking-wide text-stone-500 uppercase">{title}</h3>
		<div class="flex h-2.5 overflow-hidden rounded-full bg-stone-100">
			{#each parts as p (p.key)}
				<div style:width="{p.share * 100}%" style:background={colors[p.key]}></div>
			{/each}
		</div>
		<ul class="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-0.5 text-xs text-stone-600">
			{#each parts as p (p.key)}
				<li class="flex items-center gap-1.5">
					<span class="inline-block size-2 rounded-full" style:background={colors[p.key]}></span>
					<span class="flex-1">{labels[p.key]?.() ?? p.key}</span>
					<span class="tabular-nums">{formatDistance(p.metres)}</span>
				</li>
			{/each}
		</ul>
	</section>
{/if}
