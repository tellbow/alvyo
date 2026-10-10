<script lang="ts">
	import { onMount } from 'svelte';
	import { refreshAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '#lib/api/client.js';
	import { primaryButton } from '#lib/components/actions.js';
	import AuthCard from '#lib/components/AuthCard.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	let status = $state<'pending' | 'ask' | 'confirming' | 'ok' | 'failed'>('pending');
	let account = $state<{ username: string; display_name: string }>();
	const token = $derived(page.url.searchParams.get('token') ?? '');

	// Whose account it is, asked in the browser only (link previews of mail
	// clients load the page too); confirmed with a click: someone may have
	// signed up with another person's address.
	onMount(async () => {
		const { data } = await api().GET('/auth/verify-email', { params: { query: { token } } });
		account = data;
		status = data ? 'ask' : 'failed';
	});

	async function confirm() {
		status = 'confirming';
		const { response } = await api().POST('/auth/verify-email', { body: { token } });
		status = response.ok ? 'ok' : 'failed';
		if (response.ok) await refreshAll(); // logged in
	}
</script>

<Seo title={m.verify_title()} index={false} />

<AuthCard title={m.verify_title()}>
	{#if (status === 'ask' || status === 'confirming') && account}
		<div class="flex flex-col gap-4">
			<p>{m.verify_question({ username: account.username, name: account.display_name })}</p>
			<button
				type="button"
				class={primaryButton}
				disabled={status === 'confirming'}
				onclick={confirm}
				data-testid="verify-confirm">{m.verify_confirm()}</button
			>
			<p class="text-sm text-stone-600">{m.verify_not_mine()}</p>
		</div>
	{:else}
		<p role="status" data-testid="verify-status">
			{#if status === 'pending'}{m.verify_pending()}{:else if status === 'ok'}{m.verify_ok()}
				<a href={resolve('/plan')} class="text-accent-ink underline">{m.nav_plan()}</a
				>{:else}{m.verify_failed()}{/if}
		</p>
	{/if}
</AuthCard>
