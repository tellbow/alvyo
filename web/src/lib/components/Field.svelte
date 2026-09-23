<script lang="ts">
	import type { HTMLInputAttributes } from 'svelte/elements';

	let {
		label,
		hint,
		error,
		value = $bindable(''),
		...rest
	}: HTMLInputAttributes & { label: string; hint?: string; error?: string } = $props();
	const id = $props.id();
</script>

<div class="flex flex-col gap-1">
	<label for={id} class="text-sm font-medium text-stone-700">{label}</label>
	<input
		{id}
		bind:value
		aria-invalid={error ? 'true' : undefined}
		aria-describedby={hint || error ? `${id}-help` : undefined}
		class="rounded-md border border-stone-300 px-3 py-2 focus:border-emerald-600 focus:ring-2 focus:ring-emerald-600/20 focus:outline-none aria-invalid:border-red-600"
		{...rest}
	/>
	{#if error}
		<p id="{id}-help" class="text-sm text-red-700">{error}</p>
	{:else if hint}
		<p id="{id}-help" class="text-sm text-stone-500">{hint}</p>
	{/if}
</div>
