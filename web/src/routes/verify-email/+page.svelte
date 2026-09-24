<script lang="ts">
	import { onMount } from 'svelte';
	import { invalidateAll } from '$app/navigation';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';

	let status = $state<'pending' | 'ok' | 'failed'>('pending');

	// Verification runs on click-through in the browser only, so link
	// previews in mail clients do not consume the token.
	onMount(async () => {
		const token = page.url.searchParams.get('token') ?? '';
		const { response } = await api().POST('/auth/verify-email', { body: { token } });
		status = response.ok ? 'ok' : 'failed';
		if (response.ok) await invalidateAll();
	});
</script>

<Seo title={m.verify_title()} index={false} />

<AuthCard title={m.verify_title()}>
	<p role="status" data-testid="verify-status">
		{#if status === 'pending'}{m.verify_pending()}{:else if status === 'ok'}{m.verify_ok()}{:else}{m.verify_failed()}{/if}
	</p>
</AuthCard>
