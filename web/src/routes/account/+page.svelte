<script lang="ts">
	import { onMount } from 'svelte';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { goto, refreshAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { api } from '#lib/api/client.js';
	import Field from '#lib/components/Field.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import OidcNotice from '#lib/account/OidcNotice.svelte';
	import SignInMethods from '#lib/account/SignInMethods.svelte';
	import Contacts from '#lib/account/Contacts.svelte';
	import Homes from '#lib/account/Homes.svelte';
	import AccessTokens from '#lib/account/AccessTokens.svelte';
	import Card from '#lib/account/Card.svelte';
	import { choose } from '#lib/util/choose.js';
	import Avatar from '#lib/components/Avatar.svelte';

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
		share_hikes?: boolean;
	}) {
		const { response } = await api().PATCH('/me', { body });
		if (response.ok) await refreshAll();
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
			await refreshAll();
			await goto(resolve('/'));
		} else if (response.status === 403) {
			error = data.user?.has_password ? m.account_delete_wrong() : m.account_delete_login_again();
		} else {
			error = m.error_generic();
		}
	}

	// The profile picture; errors as for photos.
	let avatarBusy = $state(false);
	let avatarError = $state('');
	async function setAvatar(e: Event & { currentTarget: HTMLInputElement }) {
		const file = e.currentTarget.files?.[0];
		e.currentTarget.value = '';
		if (!file) return;
		avatarBusy = true;
		avatarError = '';
		const { response } = await api().PUT('/me/avatar', {
			body: { file: '' },
			bodySerializer: () => {
				const fd = new FormData();
				fd.append('file', file);
				return fd;
			}
		});
		avatarBusy = false;
		if (response.ok) await refreshAll();
		else
			avatarError = (
				{ 413: m.photos_problem_size, 415: m.photos_problem_format, 429: m.photos_problem_rate }[
					response.status
				] ?? m.photos_problem_other
			)();
	}
	async function removeAvatar() {
		const { response } = await api().DELETE('/me/avatar');
		if (response.ok) await refreshAll();
	}

	// A lost phone or a browser elsewhere: all sessions but this one end.
	let loggedOut = $state(false);
	async function logoutOthers() {
		const { response } = await api().POST('/auth/logout-others');
		loggedOut = response.ok;
	}
</script>

<Seo title={m.account_title()} index={false} />

<!-- Cards in the groups and order of the app's profile tab. -->
<main class="mx-auto w-full max-w-5xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold text-stone-900">{m.account_title()}</h1>
	<p class="mt-1 mb-6 text-stone-600">{data.user?.username} · {data.user?.email}</p>
	<OidcNotice />

	<div class="grid items-start gap-4 lg:grid-cols-2">
		<Card
			title={m.account_profile()}
			info={[m.account_profile_public_hint(), m.account_pace_hint()]}
		>
			<div class="flex flex-col gap-4 text-sm">
				<div class="flex flex-wrap items-center gap-3" data-testid="avatar">
					<Avatar id={data.user?.avatar} class="size-16" />
					<label
						class="cursor-pointer rounded-md px-3 py-1.5 ring-1 ring-stone-300 hover:bg-stone-50"
						class:opacity-50={!hydrated.value || avatarBusy}
					>
						{data.user?.avatar ? m.account_avatar_change() : m.account_avatar_add()}
						<input
							type="file"
							accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
							class="sr-only"
							disabled={!hydrated.value || avatarBusy}
							onchange={setAvatar}
							data-testid="avatar-file"
						/>
					</label>
					{#if data.user?.avatar}
						<button
							type="button"
							class="text-stone-600 underline hover:text-accent-ink"
							disabled={!hydrated.value}
							onclick={removeAvatar}>{m.account_avatar_remove()}</button
						>
					{/if}
					{#if avatarError}
						<p class="w-full text-xs text-red-700 dark:text-red-400" role="alert">{avatarError}</p>
					{/if}
				</div>
				{#if data.user}
					<a
						href={resolve('/u/[username]', { username: data.user.username })}
						class="text-accent-ink underline">{m.account_view_profile()}</a
					>
				{/if}
				<label class="flex items-center gap-2">
					<input
						type="checkbox"
						checked={data.user?.profile_public}
						disabled={!hydrated.value}
						onchange={(e) => notify({ profile_public: e.currentTarget.checked })}
						data-testid="profile-public"
					/>
					{m.account_profile_public()}
				</label>
				<label class="flex items-center gap-2">
					<input
						type="checkbox"
						checked={data.user?.share_hikes}
						disabled={!hydrated.value}
						onchange={(e) => notify({ share_hikes: e.currentTarget.checked })}
						data-testid="share-hikes"
					/>
					{m.account_share_hikes()}
				</label>
				<label class="flex flex-wrap items-center gap-x-3 gap-y-1">
					<span class="font-medium">{m.account_pace()}</span>
					<select
						class="rounded-md border border-stone-400 bg-surface px-2 py-1.5"
						aria-label={m.account_pace()}
						data-testid="pace"
						value={pace}
						disabled={!hydrated.value}
						use:choose={(v) => notify({ speed_factor: Number(v) })}
					>
						{#each paces as p (p)}
							<option value={p}
								>{p === 1 ? m.account_pace_signposts() : `${Math.round(p * 100)} %`}</option
							>
						{/each}
					</select>
				</label>
			</div>
		</Card>

		<Card title={m.account_notifications()}>
			<div class="flex flex-col gap-2 text-sm" data-testid="notifications">
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
		</Card>

		<Card title={m.account_security()} info={m.account_sessions_hint()}>
			<div class="flex flex-col gap-5">
				{#if data.user}
					<div>
						<h3 class="mb-1 font-medium">{m.signin_title()}</h3>
						<SignInMethods user={data.user} />
					</div>
				{/if}
				<div class="text-sm">
					<h3 class="font-medium">{m.account_sessions_title()}</h3>
					<div class="mt-2 flex flex-wrap items-center gap-3">
						<button
							type="button"
							class="rounded-md border border-stone-400 px-3 py-1.5 hover:bg-stone-100"
							onclick={logoutOthers}
							data-testid="logout-others">{m.account_logout_others()}</button
						>
						<p role="status" class="text-accent-ink">
							{loggedOut ? m.account_logout_others_done() : ''}
						</p>
					</div>
				</div>
			</div>
		</Card>

		<Card title={m.import_title()}>
			<p class="text-sm text-stone-600">{m.import_intro()}</p>
			<a
				href={resolve('/import')}
				class="{primaryButtonSmall} mt-3 inline-block"
				data-testid="account-import">{m.import_link()}</a
			>
		</Card>
		<Card title={m.homes_title()} info={m.homes_intro()}><Homes /></Card>

		<Card title={m.contacts_title()} info={m.contacts_intro()}><Contacts /></Card>

		{#if blocked.length > 0}
			<Card title={m.account_blocked()}>
				<ul class="flex flex-col gap-1 text-sm" data-testid="blocked">
					{#each blocked as b (b.username)}
						<li class="flex items-center gap-3">
							<span class="flex-1"
								>{b.display_name} <span class="text-stone-500">@{b.username}</span></span
							>
							<button
								type="button"
								class="text-stone-500 underline"
								onclick={() => unblock(b.username)}>{m.profile_unblock()}</button
							>
						</li>
					{/each}
				</ul>
			</Card>
		{/if}

		<Card title={m.account_developers()} collapsed testid="developers" class="lg:col-span-2">
			<h3 class="mb-1 text-sm font-medium">{m.tokens_title()}</h3>
			<AccessTokens />
		</Card>

		<Card title={m.account_delete_title()} danger class="lg:col-span-2">
			<p class="mb-4 text-sm text-stone-600">{m.account_delete_text()}</p>
			<form method="post" onsubmit={remove} class="flex max-w-md flex-col gap-3">
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
		</Card>
	</div>
</main>
