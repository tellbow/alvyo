<script lang="ts">
	import { onMount, type Snippet } from 'svelte';
	import { m } from '#lib/paraglide/messages.js';

	let { children }: { children: Snippet } = $props();

	// Folded away it leaves the map free; remembered in this browser. Without
	// a choice it starts folded on a phone, where the map is small.
	const KEY = 'alvyo.profileFolded';
	let folded = $state(false);
	onMount(() => {
		let chosen: string | null = null;
		try {
			chosen = localStorage.getItem(KEY);
		} catch {
			// storage blocked: as without a choice
		}
		folded = chosen === null ? matchMedia('(max-width: 767px)').matches : chosen === '1';
	});

	function fold(on: boolean) {
		folded = on;
		try {
			localStorage.setItem(KEY, on ? '1' : '0');
		} catch {
			// storage blocked: the choice lasts for this page
		}
	}
</script>

{#if folded}
	<button
		type="button"
		class="absolute bottom-8 left-2 z-10 rounded-full bg-surface px-3 py-1.5 text-sm font-medium shadow ring-1 ring-stone-300 hover:bg-stone-100"
		aria-expanded="false"
		onclick={() => fold(false)}
		data-testid="profile-show">{m.profile_title()}</button
	>
{:else}
	<div
		class="absolute right-12 bottom-8 left-2 z-10 rounded-md bg-surface/95 px-2 py-1 shadow ring-1 ring-stone-300"
	>
		<button
			type="button"
			class="absolute top-0 right-0 z-10 icon-button"
			aria-label={m.profile_hide()}
			title={m.profile_hide()}
			aria-expanded="true"
			onclick={() => fold(true)}
			data-testid="profile-hide"
		>
			<svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
				<path d="M6 9l6 6 6-6" stroke="currentColor" stroke-width="2" />
			</svg>
		</button>
		{@render children()}
	</div>
{/if}
