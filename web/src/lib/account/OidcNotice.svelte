<script lang="ts">
	import { page } from '$app/state';
	import { m } from '$lib/paraglide/messages';

	// Outcomes of a provider sign-in, passed back as ?oidc=… by the API.
	const messages: Record<string, { text: () => string; ok?: boolean }> = {
		exists: { text: m.oidc_exists },
		noemail: { text: m.oidc_noemail },
		banned: { text: m.oidc_banned },
		failed: { text: m.oidc_failed },
		cancelled: { text: m.oidc_cancelled },
		unavailable: { text: m.oidc_unavailable },
		busy: { text: m.error_too_many },
		taken: { text: m.oidc_taken },
		already: { text: m.oidc_already },
		verify: { text: m.oidc_verify },
		again: { text: m.oidc_again },
		linked: { text: m.oidc_linked, ok: true }
	};
	const outcome = $derived(page.url.searchParams.get('oidc') ?? '');
	// Own keys only: ?oidc=constructor is not a message.
	const notice = $derived(Object.hasOwn(messages, outcome) ? messages[outcome] : undefined);
</script>

{#if notice}
	<p
		role={notice.ok ? 'status' : 'alert'}
		class="mb-4 rounded-md px-3 py-2 text-sm {notice.ok
			? 'bg-accent-soft text-accent-ink'
			: 'bg-amber-50 text-amber-900 dark:bg-amber-950/40 dark:text-amber-200'}"
		data-testid="oidc-notice"
	>
		{notice.text()}
	</p>
{/if}
