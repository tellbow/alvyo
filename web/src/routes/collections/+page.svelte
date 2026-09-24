<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import TagChips from '$lib/tags/TagChips.svelte';
	import TagFilter from '$lib/tags/TagFilter.svelte';
	import { hasTag } from '$lib/tags/tags';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	let { data } = $props();
	const hydrated = new Hydrated();
	let title = $state('');
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	const collections = $derived(data.collections.filter((c) => hasTag(c.tags, tag)));
	const byTag = (t: string) => `?tag=${encodeURIComponent(t)}`;

	async function create(e: SubmitEvent) {
		e.preventDefault();
		const { data: c } = await api().POST('/collections', {
			body: { title: title.trim(), visibility: 'private' }
		});
		if (c) await goto(resolve('/collections/[id]', { id: c.id }));
	}

	async function leave(id: string) {
		const { response } = await api().DELETE('/collections/{id}/access', {
			params: { path: { id } }
		});
		if (response.ok) shared = shared.filter((c) => c.id !== id);
	}
</script>

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.collections_title()}</h1>
	<p class="mt-1 text-stone-600">{m.collections_intro()}</p>

	<form method="post" onsubmit={create} class="mt-6 flex gap-2">
		<input
			bind:value={title}
			required
			maxlength="120"
			placeholder={m.collection_new()}
			aria-label={m.field_title()}
			class="flex-1 rounded-md border border-stone-300 px-3 py-2"
		/>
		<button
			disabled={!hydrated.value}
			class="rounded-md bg-emerald-700 px-4 py-2 text-white hover:bg-emerald-800"
		>
			{m.journey_create()}
		</button>
	</form>

	<div class="mt-6"><TagFilter /></div>
	{#if data.collections.length === 0}
		<p class="mt-6 text-stone-600">{m.collections_empty()}</p>
	{:else}
		<ul
			class="mt-6 divide-y divide-stone-200 rounded-md border border-stone-200 bg-white"
			data-testid="collection-list"
		>
			{#each collections as c (c.id)}
				<!-- The title's link covers the row; the tags link above it. -->
				<li class="relative flex items-center gap-4 px-4 py-3 hover:bg-stone-50">
					<span class="flex flex-1 flex-col gap-1">
						<a
							href={resolve('/collections/[id]', { id: c.id })}
							class="font-medium after:absolute after:inset-0">{c.title}</a
						>
						<TagChips tags={c.tags} href={byTag} />
					</span>
					<span class="text-sm text-stone-600">{m.collection_items_count({ n: c.items })}</span>
				</li>
			{/each}
		</ul>
	{/if}

	{#if shared.length > 0}
		<h2 class="mt-8 mb-2 text-lg font-semibold">{m.shared_title()}</h2>
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-white"
			data-testid="shared-collections"
		>
			{#each shared as c (c.id)}
				<li class="flex items-center gap-4 px-4 py-3">
					<a
						href={resolve('/collections/[id]', { id: c.id })}
						class="flex-1 font-medium hover:underline">{c.title}</a
					>
					<span class="text-sm text-stone-600">{m.shared_by({ user: c.owner_username })}</span>
					<span class="w-28 text-xs text-stone-500"
						>{c.role === 'editor' ? m.role_editor() : m.role_viewer()}</span
					>
					<button type="button" class="text-xs text-stone-500 underline" onclick={() => leave(c.id)}
						>{m.shared_leave()}</button
					>
				</li>
			{/each}
		</ul>
	{/if}
</main>
