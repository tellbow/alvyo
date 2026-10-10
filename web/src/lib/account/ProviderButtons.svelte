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
	<a
		href={start(p.id)}
		rel="external"
		class="rounded-md px-4 py-2 text-center ring-1 ring-stone-300 hover:bg-stone-50"
		data-testid="provider-{p.id}">{label(p.name)}</a
	>
{/each}
