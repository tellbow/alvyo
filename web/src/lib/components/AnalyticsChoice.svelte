<script lang="ts">
	import { onMount } from 'svelte';
	import { analyticsActive, readConsent, setConsent, type Consent } from '$lib/analytics';
	import { m } from '$lib/paraglide/messages';

	// «Statistik» on the about page: the choice of the banner, changed here.
	let active = $state(false);
	let consent = $state<Consent>();
	onMount(() => {
		active = analyticsActive();
		consent = readConsent();
	});

	function choose(c: Consent) {
		setConsent(c);
		consent = c;
	}
</script>

{#if active}
	<section id="statistics" data-testid="analytics-choice">
		<h2 class="mt-8 text-lg font-semibold">{m.analytics_title()}</h2>
		<p class="mt-2">
			{consent === 'granted'
				? m.analytics_granted()
				: consent === 'denied'
					? m.analytics_denied()
					: m.analytics_undecided()}
		</p>
		<div class="mt-2 flex gap-2 text-sm">
			{#if consent !== 'granted'}
				<button
					type="button"
					class="rounded-md px-3 py-1.5 ring-1 ring-stone-300 hover:bg-stone-100"
					onclick={() => choose('granted')}>{m.analytics_accept()}</button
				>
			{/if}
			{#if consent !== 'denied'}
				<button
					type="button"
					class="rounded-md px-3 py-1.5 ring-1 ring-stone-300 hover:bg-stone-100"
					onclick={() => choose('denied')}>{m.analytics_decline()}</button
				>
			{/if}
		</div>
	</section>
{/if}
