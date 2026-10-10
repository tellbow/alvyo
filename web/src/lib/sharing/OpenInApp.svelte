<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { m } from '#lib/paraglide/messages.js';

	// On an iPhone or iPad, a link that opens this route, journey, collection
	// or friend's invite (id: its token) in the app (its own scheme: universal
	// links need a paid developer account); the share token rides along.
	let {
		kind,
		id,
		class: className = 'text-sm text-accent-ink underline'
	}: {
		kind: 'routes' | 'journeys' | 'collections' | 'friends/invite';
		id: string;
		class?: string;
	} = $props();

	let ios = $state(false);
	onMount(() => {
		// iPadOS reports itself as a Mac with touch.
		ios =
			/iPhone|iPad|iPod/.test(navigator.userAgent) ||
			(navigator.userAgent.includes('Macintosh') && navigator.maxTouchPoints > 1);
	});
	const href = $derived.by(() => {
		const t = page.url.searchParams.get('t');
		return `alvyo://open/${kind}/${id}${t ? `?t=${encodeURIComponent(t)}` : ''}`;
	});
</script>

{#if ios}
	<!-- The app's own scheme: resolve() does not apply. -->
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
	<a {href} class={className} data-testid="open-in-app">{m.open_in_app()}</a>
{/if}
