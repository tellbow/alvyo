<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import { analyticsActive, readConsent, setConsent, type Consent } from '#lib/analytics.js';
	import { m } from '#lib/paraglide/messages.js';

	// Asks once whether Google Analytics may set cookies; both answers alike.
	let open = $state(false);
	onMount(() => {
		open = analyticsActive() && !readConsent();
	});

	function choose(c: Consent) {
		setConsent(c);
		open = false;
	}

	const answer = 'rounded-md px-4 py-1.5 font-medium ring-1 ring-stone-300 hover:bg-stone-100';
</script>

{#if open}
	<div
		role="region"
		aria-label={m.analytics_title()}
		class="fixed inset-x-3 bottom-3 z-50 mx-auto max-w-lg rounded-xl border border-stone-200 bg-surface p-4 text-sm shadow-lg print:hidden"
		data-testid="consent"
	>
		<p>
			{m.analytics_banner()}
			<a href="{resolve('/about')}#statistics" class="text-accent-ink underline"
				>{m.about_privacy_title()}</a
			>
		</p>
		<div class="mt-3 flex justify-end gap-2">
			<button type="button" class={answer} onclick={() => choose('denied')}
				>{m.analytics_decline()}</button
			>
			<button type="button" class={answer} onclick={() => choose('granted')}
				>{m.analytics_accept()}</button
			>
		</div>
	</div>
{/if}
