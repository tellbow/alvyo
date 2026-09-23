<script lang="ts">
	import type { Snippet } from 'svelte';

	let { title, children }: { title: string; children: Snippet } = $props();
</script>

<main class="mx-auto mt-12 w-full max-w-sm px-4">
	<h1 class="mb-6 text-2xl font-semibold text-stone-900">{title}</h1>
	{@render children()}
</main>
