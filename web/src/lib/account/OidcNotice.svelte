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
		linked: { text: m.oidc_linked, ok: true }
	};
	const notice = $derived(messages[page.url.searchParams.get('oidc') ?? '']);
</script>

{#if notice}
	<p
		role={notice.ok ? 'status' : 'alert'}
		class="mb-4 rounded-md px-3 py-2 text-sm {notice.ok
			? 'bg-emerald-50 text-emerald-900'
			: 'bg-amber-50 text-amber-900'}"
		data-testid="oidc-notice"
	>
		{notice.text()}
	</p>
{/if}
