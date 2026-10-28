<script lang="ts">
	import { resolve } from '$app/paths';
	import { refreshAll } from '$app/navigation';
	import { page } from '$app/state';
	import UsersIcon from '@lucide/svelte/icons/users';
	import { api } from '#lib/api/client.js';
	import type { components } from '#lib/api/schema.js';
	import { mainAction } from '#lib/components/actions.js';
	import FriendButton from '#lib/community/FriendButton.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	type FriendRef = components['schemas']['FriendRef'];
	let { data } = $props();

	// Search as one types, public profiles only; without a term, those who
	// published lately.
	let q = $state('');
	let found = $state<FriendRef[]>();
	let timer: ReturnType<typeof setTimeout> | undefined;
	function search() {
		clearTimeout(timer);
		const term = q.trim();
		if (term.length < 2) {
			found = undefined;
			return;
		}
		timer = setTimeout(async () => {
			const { data: r } = await api().GET('/users', { params: { query: { q: term } } });
			if (r && q.trim() === term) found = r.users;
		}, 250);
	}
	const shown = $derived(found ?? data.profiles);

	// Loaded anew after a change; a dismissed one leaves at once.
	let suggestions = $derived(data.suggestions);
	async function dismiss(username: string) {
		const { response } = await api().DELETE('/me/friend-suggestions/{username}', {
			params: { path: { username } }
		});
		if (response.ok) suggestions = suggestions.filter((f) => f.username !== username);
	}

	// svelte-ignore state_referenced_locally
	let token = $state(data.token);
	let copied = $state(false);
	const link = $derived(token ? `${page.url.origin}/friends/invite/${token}` : '');
	async function invite() {
		if (navigator.share) {
			await navigator.share({ url: link }).catch(() => {});
			return;
		}
		await navigator.clipboard.writeText(link);
		copied = true;
	}
	async function rotate() {
		const { data: r } = await api().POST('/me/friend-link');
		if (r) {
			token = r.token;
			copied = false;
		}
	}

	const initials = (name: string) =>
		name
			.split(/\s+/)
			.filter(Boolean)
			.slice(0, 2)
			.map((w) => w[0].toUpperCase())
			.join('');
	const section = 'mt-10 mb-3 font-display text-lg font-bold';
	const grid = 'grid gap-3 sm:grid-cols-2';
</script>

{#snippet person(f: FriendRef, testid: string, suggested = false)}
	<li class="flex gap-3 rounded-xl border border-stone-200 bg-surface p-4" data-testid={testid}>
		<div
			class="flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-soft font-display font-bold text-accent-ink"
			aria-hidden="true"
		>
			{initials(f.display_name)}
		</div>
		<div class="min-w-0 flex-1">
			<div class="flex items-start gap-2">
				<p class="min-w-0 flex-1 truncate">
					<a
						href={resolve('/u/[username]', { username: f.username })}
						class="font-semibold hover:underline">{f.display_name}</a
					>
					<span class="block truncate text-sm text-stone-500">@{f.username}</span>
				</p>
				{#if suggested}
					<button
						type="button"
						class="-m-1 rounded-full p-1 text-stone-500 hover:bg-muted hover:text-foreground"
						aria-label={m.friends_dismiss()}
						title={m.friends_dismiss()}
						onclick={() => dismiss(f.username)}
						data-testid="dismiss">✕</button
					>
				{/if}
			</div>
			<p class="mt-1 text-[13px] text-stone-600">
				{#if f.friend === 'incoming'}
					{m.friend_incoming()}
				{:else}
					{[
						f.tours > 0 && m.friends_tours({ n: f.tours }),
						f.mutual > 0 && m.friends_mutual({ n: f.mutual })
					]
						.filter(Boolean)
						.join(' · ')}
				{/if}
			</p>
			<!-- A change moves the person between the lists: loaded anew. -->
			<div class="mt-2 text-sm">
				<FriendButton
					username={f.username}
					friend={f.friend}
					primary={mainAction}
					onchange={() => refreshAll()}
				/>
			</div>
		</div>
	</li>
{/snippet}

<Seo title={m.friends_title()} index={false} />

<main class="mx-auto w-full max-w-3xl overflow-y-auto px-4 py-8">
	<h1 class="font-display text-2xl font-bold">{m.friends_title()}</h1>
	<p class="mt-1 text-stone-600">{m.friends_intro()}</p>

	{#if link}
		<div class="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
			<button type="button" class={mainAction} onclick={invite} data-testid="friend-invite-link">
				{copied ? m.friends_link_copied() : m.friends_invite()}
			</button>
			<button
				type="button"
				class="text-stone-600 underline"
				title={m.share_rotate_hint()}
				onclick={rotate}>{m.share_rotate()}</button
			>
		</div>
		<p class="mt-2 text-xs text-stone-500">{m.friends_link_hint()}</p>
	{/if}

	{#if data.lists.incoming.length > 0}
		<h2 class={section}>{m.friends_incoming()}</h2>
		<ul class={grid} data-testid="friends-incoming">
			{#each data.lists.incoming as f (f.username)}
				{@render person(f, 'incoming')}
			{/each}
		</ul>
	{/if}

	<h2 class={section}>{m.friends_list()}</h2>
	{#if data.lists.friends.length === 0}
		<div
			class="flex flex-col items-center rounded-xl border border-stone-200 bg-surface px-5 py-8 text-center"
		>
			<div
				class="flex size-14 items-center justify-center rounded-full bg-accent-soft text-accent-ink"
				aria-hidden="true"
			>
				<UsersIcon class="size-7" />
			</div>
			<p class="mt-3 max-w-sm text-stone-600">{m.friends_empty()}</p>
			{#if link}
				<button type="button" class="mt-4 text-sm {mainAction}" onclick={invite}>
					{copied ? m.friends_link_copied() : m.friends_invite()}
				</button>
			{/if}
		</div>
	{:else}
		<ul class={grid} data-testid="friends-list">
			{#each data.lists.friends as f (f.username)}
				{@render person(f, 'friend')}
			{/each}
		</ul>
	{/if}

	{#if suggestions.length > 0}
		<h2 class={section}>{m.friends_suggestions()}</h2>
		<ul class={grid} data-testid="friends-suggested">
			{#each suggestions as f (f.username)}
				{@render person(f, 'suggested', true)}
			{/each}
		</ul>
	{/if}

	{#if data.lists.outgoing.length > 0}
		<h2 class={section}>{m.friends_outgoing()}</h2>
		<ul class={grid} data-testid="friends-outgoing">
			{#each data.lists.outgoing as f (f.username)}
				{@render person(f, 'outgoing')}
			{/each}
		</ul>
	{/if}

	<h2 class={section}>{m.friends_discover()}</h2>
	<input
		type="search"
		bind:value={q}
		oninput={search}
		autocomplete="off"
		aria-label={m.friends_search()}
		placeholder={m.friends_search()}
		class="w-full rounded-md border border-stone-400 bg-surface px-3 py-2"
		data-testid="friends-search"
	/>
	<p class="mt-1 text-xs text-stone-500">{m.friends_search_hint()}</p>
	{#if shown.length === 0}
		<p class="mt-3 text-sm text-stone-600">{m.friends_none_found()}</p>
	{:else}
		<ul class="mt-3 {grid}" data-testid={found ? 'friends-found' : 'friends-profiles'}>
			{#each shown as f (f.username)}
				{@render person(f, 'found')}
			{/each}
		</ul>
	{/if}
</main>
