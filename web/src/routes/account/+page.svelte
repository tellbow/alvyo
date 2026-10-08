<script lang="ts">
	import { onMount } from 'svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import Field from '$lib/components/Field.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import OidcNotice from '$lib/account/OidcNotice.svelte';
	import SignInMethods from '$lib/account/SignInMethods.svelte';
	import Contacts from '$lib/account/Contacts.svelte';
	import Homes from '$lib/account/Homes.svelte';
	import { choose } from '$lib/util/choose';

	let { data } = $props();
	const hydrated = new Hydrated();
	let password = $state('');
	let error = $state('');
	let blocked = $state<{ username: string; display_name: string }[]>([]);

	onMount(async () => {
		const { data: b } = await api().GET('/me/blocks');
		blocked = b?.users ?? [];
	});

	// Hiking times as a multiple of the signposts' (1.2: a fifth slower).
	const PACES = [0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2];
	const pace = $derived(data.user?.speed_factor ?? 1);
	const paces = $derived(PACES.includes(pace) ? PACES : [...PACES, pace].sort((a, b) => a - b));

	async function notify(body: {
		notify_comments?: boolean;
		notify_follows?: boolean;
		speed_factor?: number;
		profile_public?: boolean;
	}) {
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

	// A lost phone or a browser elsewhere: all sessions but this one end.
	let loggedOut = $state(false);
	async function logoutOthers() {
		const { response } = await api().POST('/auth/logout-others');
		loggedOut = response.ok;
	}
</script>

<Seo title={m.account_title()} index={false} />

<AuthCard title={m.account_title()}>
	<OidcNotice />
	<p class="text-stone-600">{data.user?.username} · {data.user?.email}</p>

	{#if data.user}<SignInMethods user={data.user} />{/if}

	<h2 class="mt-8 text-lg font-semibold">{m.account_sessions_title()}</h2>
	<p class="mt-1 text-sm text-stone-600">{m.account_sessions_hint()}</p>
	<div class="mt-2 flex flex-wrap items-center gap-3">
		<button
			type="button"
			class="rounded-md border border-stone-400 px-3 py-1.5 text-sm hover:bg-stone-100"
			onclick={logoutOthers}
			data-testid="logout-others">{m.account_logout_others()}</button
		>
		<p role="status" class="text-sm text-accent-ink">
			{loggedOut ? m.account_logout_others_done() : ''}
		</p>
	</div>

	<h2 class="mt-8 text-lg font-semibold">{m.account_pace()}</h2>
	<p class="mt-1 text-sm text-stone-600">{m.account_pace_hint()}</p>
	<select
		class="mt-2 rounded-md border border-stone-400 bg-surface px-2 py-1.5 text-sm"
		aria-label={m.account_pace()}
		data-testid="pace"
		value={pace}
		disabled={!hydrated.value}
		use:choose={(v) => notify({ speed_factor: Number(v) })}
	>
		{#each paces as p (p)}
			<option value={p}>{p === 1 ? m.account_pace_signposts() : `${Math.round(p * 100)} %`}</option>
		{/each}
	</select>

	<h2 class="mt-8 text-lg font-semibold">{m.account_profile()}</h2>
	<label class="mt-2 flex items-center gap-2 text-sm">
		<input
			type="checkbox"
			checked={data.user?.profile_public}
			disabled={!hydrated.value}
			onchange={(e) => notify({ profile_public: e.currentTarget.checked })}
			data-testid="profile-public"
		/>
		{m.account_profile_public()}
	</label>
	<p class="mt-1 text-xs text-stone-500">{m.account_profile_public_hint()}</p>

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

	<Contacts />

	<Homes />

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

	<h2 class="mt-8 text-lg font-semibold text-red-800 dark:text-red-300">
		{m.account_delete_title()}
	</h2>
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
		{#if error}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{error}</p>{/if}
		<button
			disabled={!hydrated.value}
			class="rounded-md bg-red-700 px-4 py-2 text-white hover:bg-red-800"
			>{m.account_delete_submit()}</button
		>
	</form>
</AuthCard>
