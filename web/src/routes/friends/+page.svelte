<script lang="ts">
	import { resolve } from '$app/paths';
	import { invalidateAll } from '$app/navigation';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import FriendButton from '$lib/community/FriendButton.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';

	type FriendRef = components['schemas']['FriendRef'];
	let { data } = $props();

	// Search as one types, public profiles only.
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

	// svelte-ignore state_referenced_locally
	let token = $state(data.token);
	let copied = $state(false);
	const link = $derived(token ? `${page.url.origin}/friends/invite/${token}` : '');
	async function copy() {
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

	const section = 'mt-8 mb-2 text-lg font-semibold';
	const list = 'divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface';
</script>

{#snippet person(f: FriendRef, testid: string)}
	<li class="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3" data-testid={testid}>
		<span class="min-w-0 flex-1">
			<a
				href={resolve('/u/[username]', { username: f.username })}
				class="font-medium hover:underline">{f.display_name}</a
			>
			<span class="text-sm text-stone-500">@{f.username}</span>
			{#if f.friend === 'incoming'}
				<span class="block text-xs text-stone-500">{m.friend_incoming()}</span>
			{/if}
		</span>
		<!-- A change moves the person between the lists: loaded anew. -->
		<FriendButton username={f.username} friend={f.friend} onchange={() => invalidateAll()} />
	</li>
{/snippet}

<Seo title={m.friends_title()} index={false} />

<main class="mx-auto w-full max-w-3xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.friends_title()}</h1>

	<label class="mt-6 block">
		<span class="text-sm font-medium">{m.friends_search()}</span>
		<input
			type="search"
			bind:value={q}
			oninput={search}
			autocomplete="off"
			class="mt-1 w-full rounded-md border border-stone-300 bg-surface px-3 py-2"
			data-testid="friends-search"
		/>
	</label>
	<p class="mt-1 text-xs text-stone-500">{m.friends_search_hint()}</p>
	{#if found}
		{#if found.length === 0}
			<p class="mt-3 text-sm text-stone-600">{m.friends_none_found()}</p>
		{:else}
			<ul class="mt-3 {list}" data-testid="friends-found">
				{#each found as f (f.username)}
					{@render person(f, 'found')}
				{/each}
			</ul>
		{/if}
	{/if}

	{#if data.lists.incoming.length > 0}
		<h2 class={section}>{m.friends_incoming()}</h2>
		<ul class={list} data-testid="friends-incoming">
			{#each data.lists.incoming as f (f.username)}
				{@render person(f, 'incoming')}
			{/each}
		</ul>
	{/if}

	<h2 class={section}>{m.friends_list()}</h2>
	{#if data.lists.friends.length === 0}
		<p class="text-sm text-stone-600">{m.friends_empty()}</p>
	{:else}
		<ul class={list} data-testid="friends-list">
			{#each data.lists.friends as f (f.username)}
				{@render person(f, 'friend')}
			{/each}
		</ul>
	{/if}

	{#if data.lists.outgoing.length > 0}
		<h2 class={section}>{m.friends_outgoing()}</h2>
		<ul class={list} data-testid="friends-outgoing">
			{#each data.lists.outgoing as f (f.username)}
				{@render person(f, 'outgoing')}
			{/each}
		</ul>
	{/if}

	<h2 class={section}>{m.friends_link_title()}</h2>
	<p class="text-sm text-stone-600">{m.friends_link_hint()}</p>
	{#if link}
		<div class="mt-2 flex gap-2" data-testid="friend-link">
			<input
				readonly
				value={link}
				class="min-w-0 flex-1 rounded-md border border-stone-300 px-2 py-1.5 text-sm"
			/>
			<button type="button" class="rounded-md px-3 text-sm ring-1 ring-stone-300" onclick={copy}
				>{copied ? m.share_copied() : m.share_copy()}</button
			>
		</div>
		<button
			type="button"
			class="mt-2 text-sm text-stone-600 underline"
			title={m.share_rotate_hint()}
			onclick={rotate}>{m.share_rotate()}</button
		>
	{/if}
</main>
