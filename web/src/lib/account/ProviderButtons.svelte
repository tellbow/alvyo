<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '#lib/api/client.js';

	let {
		redirect = '/',
		link = false,
		exclude = [],
		label
	}: {
		/** Where to return after logging in. */
		redirect?: string;
		/** Connect the provider to the logged-in account. */
		link?: boolean;
		/** Providers not to offer (already connected). */
		exclude?: string[];
		label: (name: string) => string;
	} = $props();

	let providers = $state<{ id: string; name: string }[]>([]);

	onMount(async () => {
		const { data } = await api().GET('/auth/providers');
		providers = data?.providers ?? [];
	});

	function start(id: string) {
		const q = new URLSearchParams(link ? { link: 'true' } : { redirect });
		return `/api/v1/auth/oidc/${encodeURIComponent(id)}/start?${q}`;
	}
</script>

{#each providers.filter((p) => !exclude.includes(p.id)) as p (p.id)}
	<!-- The API redirects to the provider: a full page load, not a SvelteKit route. -->
	{#if p.id === 'apple'}
		<!-- Apple's guidelines: black with its logo, white on a dark page. -->
		<a
			href={start(p.id)}
			rel="external"
			class="flex items-center justify-center gap-2 rounded-md bg-black px-4 py-2 font-medium text-white hover:bg-stone-800 dark:bg-white dark:text-black dark:hover:bg-stone-200"
			data-testid="provider-{p.id}"
			><svg viewBox="0 0 24 24" class="size-4" fill="currentColor" aria-hidden="true"
				><path
					d="M12.15 6.9c-.95 0-2.42-1.08-3.96-1.04-2.04.03-3.91 1.18-4.96 3.01-2.12 3.68-.55 9.1 1.52 12.09 1.01 1.45 2.2 3.09 3.79 3.04 1.52-.07 2.09-.99 3.94-.99 1.83 0 2.35.99 3.96.95 1.64-.03 2.68-1.48 3.68-2.95 1.16-1.69 1.64-3.33 1.66-3.42-.04-.01-3.18-1.22-3.22-4.86-.03-3.04 2.48-4.49 2.6-4.56-1.43-2.09-3.62-2.32-4.39-2.38-2-.16-3.68 1.09-4.61 1.09zm3.38-3.07c.84-1.01 1.4-2.43 1.25-3.83-1.21.05-2.66.8-3.53 1.82-.78.9-1.45 2.34-1.27 3.71 1.34.1 2.71-.69 3.56-1.7"
				/></svg
			>{label(p.name)}</a
		>
	{:else}
		<a
			href={start(p.id)}
			rel="external"
			class="rounded-md px-4 py-2 text-center ring-1 ring-stone-300 hover:bg-stone-50"
			data-testid="provider-{p.id}">{label(p.name)}</a
		>
	{/if}
{/each}
