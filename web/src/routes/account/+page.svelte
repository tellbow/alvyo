<script lang="ts">
	import { onMount } from 'svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import Field from '$lib/components/Field.svelte';
	import { m } from '$lib/paraglide/messages';
	import OidcNotice from '$lib/account/OidcNotice.svelte';
	import SignInMethods from '$lib/account/SignInMethods.svelte';

	let { data } = $props();
	const hydrated = new Hydrated();
	let password = $state('');
	let error = $state('');
	let blocked = $state<{ username: string; display_name: string }[]>([]);

	onMount(async () => {
		const { data: b } = await api().GET('/me/blocks');
		blocked = b?.users ?? [];
	});

	async function notify(body: { notify_comments?: boolean; notify_follows?: boolean }) {
		const { response } = await api().PATCH('/me', { body });
		if (response.ok) await invalidateAll();
	}

	async function unblock(username: string) {
		const { response } = await api().DELETE('/users/{username}/block', {
			params: { path: { username } }
		});
		if (response.ok) blocked = blocked.filter((u) => u.username !== username);
	}

	async function remove(e: SubmitEvent) {
		e.preventDefault();
		const { response } = await api().DELETE('/me', { body: password ? { password } : {} });
		if (response.ok) {
			await invalidateAll();
			await goto(resolve('/'));
		} else if (response.status === 403) {
			error = data.user?.has_password ? m.account_delete_wrong() : m.account_delete_login_again();
		} else {
			error = m.error_generic();
		}
	}
</script>

<AuthCard title={m.account_title()}>
	<OidcNotice />
	<p class="text-stone-600">{data.user?.username} · {data.user?.email}</p>

	{#if data.user}<SignInMethods user={data.user} />{/if}

	<h2 class="mt-8 text-lg font-semibold">{m.account_notifications()}</h2>
	<div class="mt-2 flex flex-col gap-2 text-sm" data-testid="notifications">
		<label class="flex items-center gap-2">
			<input
				type="checkbox"
				checked={data.user?.notify_comments}
				disabled={!hydrated.value}
				onchange={(e) => notify({ notify_comments: e.currentTarget.checked })}
			/>
			{m.account_notify_comments()}
		</label>
		<label class="flex items-center gap-2">
			<input
				type="checkbox"
				checked={data.user?.notify_follows}
				disabled={!hydrated.value}
				onchange={(e) => notify({ notify_follows: e.currentTarget.checked })}
			/>
			{m.account_notify_follows()}
		</label>
	</div>

	{#if blocked.length > 0}
		<h2 class="mt-8 text-lg font-semibold">{m.account_blocked()}</h2>
		<ul class="mt-2 flex flex-col gap-1 text-sm" data-testid="blocked">
			{#each blocked as b (b.username)}
				<li class="flex items-center gap-3">
					<span class="flex-1"
						>{b.display_name} <span class="text-stone-500">@{b.username}</span></span
					>
					<button type="button" class="text-stone-500 underline" onclick={() => unblock(b.username)}
						>{m.profile_unblock()}</button
					>
				</li>
			{/each}
		</ul>
	{/if}

	<h2 class="mt-8 text-lg font-semibold text-red-800">{m.account_delete_title()}</h2>
	<p class="mt-1 mb-4 text-sm text-stone-600">{m.account_delete_text()}</p>
	<form method="post" onsubmit={remove} class="flex flex-col gap-3">
		{#if data.user?.has_password}
			<Field
				label={m.field_password()}
				name="password"
				type="password"
				autocomplete="current-password"
				required
				bind:value={password}
			/>
		{:else}
			<p class="text-sm text-stone-600">{m.account_delete_recent()}</p>
		{/if}
		{#if error}<p role="alert" class="text-sm text-red-700">{error}</p>{/if}
		<button
			disabled={!hydrated.value}
			class="rounded-md bg-red-700 px-4 py-2 text-white hover:bg-red-800"
			>{m.account_delete_submit()}</button
		>
	</form>
</AuthCard>
