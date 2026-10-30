<script lang="ts">
	import { page } from '$app/state';

	/** A search that keeps its term in the address (?q=). */
	let { label, placeholder }: { label: string; placeholder: string } = $props();
</script>

<form method="get" class="mb-6 flex gap-2" role="search">
	<input
		type="search"
		name="q"
		value={page.url.searchParams.get('q') ?? ''}
		aria-label={label}
		{placeholder}
		class="h-10 flex-1 rounded-lg border border-stone-300 bg-surface px-3"
	/>
	<button type="submit" class="rounded-lg border border-stone-300 px-4 hover:bg-stone-100"
		>Suchen</button
	>
</form>
