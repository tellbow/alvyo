<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	// Someone's invite link: whoever opens it and agrees becomes their friend.
	let { data } = $props();
	const hydrated = new Hydrated();
	let status = $state<'idle' | 'busy' | 'done' | 'failed'>('idle');
	const self = $derived(data.user?.username === data.inviter?.username);

	async function accept() {
		status = 'busy';
		const { response } = await api().POST('/friend-invites/{token}', {
			params: { path: { token: page.params.token! } }
		});
		status = response.ok ? 'done' : 'failed';
	}
</script>

<Seo title={m.friends_title()} index={false} />

<main class="mx-auto w-full max-w-md overflow-y-auto px-4 py-12" data-testid="friend-invite">
	{#if !data.inviter}
		<p>{m.friend_invite_invalid()}</p>
	{:else}
		<h1 class="text-2xl font-semibold">
			{m.friend_invite_title({ name: data.inviter.display_name })}
		</h1>
		<p class="mt-1 text-stone-500">@{data.inviter.username}</p>
		<p class="mt-4">{m.friend_invite_text()}</p>
		{#if self}
			<p class="mt-6 text-stone-600">{m.friend_invite_self()}</p>
		{:else if !data.user}
			<!-- resolve() gives the path; only the query is added -->
			<!-- eslint-disable svelte/no-navigation-without-resolve -->
			<a
				href={`${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname)}`}
				class="mt-6 inline-block rounded-md bg-accent px-4 py-2 text-on-accent hover:bg-accent-hover"
				>{m.friend_invite_login()}</a
			>
			<!-- eslint-enable svelte/no-navigation-without-resolve -->
		{:else if status === 'done'}
			<p class="mt-6 font-medium" role="status">{m.friend_invite_done()}</p>
			<a
				href={resolve('/u/[username]', { username: data.inviter.username })}
				class="mt-2 inline-block text-accent-ink underline">@{data.inviter.username}</a
			>
		{:else}
			<button
				type="button"
				class="mt-6 rounded-md bg-accent px-4 py-2 text-on-accent hover:bg-accent-hover disabled:opacity-60"
				disabled={!hydrated.value || status === 'busy'}
				onclick={accept}
				data-testid="friend-invite-accept">{m.friend_invite_accept()}</button
			>
			{#if status === 'failed'}
				<p class="mt-2 text-sm text-red-700 dark:text-red-400" role="alert">{m.error_generic()}</p>
			{/if}
		{/if}
	{/if}
</main>
