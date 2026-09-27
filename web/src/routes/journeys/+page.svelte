<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { formatDistance, formatDuration } from '$lib/planner/route';
	import TagChips from '$lib/tags/TagChips.svelte';
	import TagFilter from '$lib/tags/TagFilter.svelte';
	import { hasTag } from '$lib/tags/tags';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	let { data } = $props();
	const hydrated = new Hydrated();
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	// Deleted here, and the one asking «really?».
	let deleted = $state<string[]>([]);
	let confirming = $state<string>();
	const journeys = $derived(
		data.journeys.filter((j) => hasTag(j.tags, tag) && !deleted.includes(j.id))
	);
	const byTag = (t: string) => `?tag=${encodeURIComponent(t)}`;

	async function leave(id: string) {
		const { response } = await api().DELETE('/journeys/{id}/access', {
			params: { path: { id } }
		});
		if (response.ok) shared = shared.filter((j) => j.id !== id);
	}

	async function remove(id: string) {
		const { response } = await api().DELETE('/journeys/{id}', { params: { path: { id } } });
		if (response.ok) deleted = [...deleted, id];
		confirming = undefined;
	}
	let title = $state('');

	async function create(e: SubmitEvent) {
		e.preventDefault();
		const { data: j } = await api().POST('/journeys', {
			body: { title: title.trim(), visibility: 'private' }
		});
		if (j) await goto(resolve('/journeys/[id]', { id: j.id }));
	}
</script>

<Seo title={m.journeys_title()} index={false} />

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.journeys_title()}</h1>
	<p class="mt-1 text-stone-600">
		{m.journeys_intro()}
		<a href={resolve('/import')} class="underline hover:text-accent-ink"
			>{m.import_journey_hint()}</a
		>
	</p>
	<a
		href={resolve('/journeys/plan')}
		class="mt-4 inline-block rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover"
		data-testid="journey-plan-link">{m.jplan_link()}</a
	>

	<form method="post" onsubmit={create} class="mt-6 flex gap-2">
		<input
			bind:value={title}
			required
			maxlength="120"
			placeholder={m.journey_new()}
			aria-label={m.field_title()}
			class="flex-1 rounded-md border border-stone-300 px-3 py-2"
		/>
		<button
			disabled={!hydrated.value}
			class="rounded-md bg-accent px-4 py-2 text-on-accent hover:bg-accent-hover"
		>
			{m.journey_create()}
		</button>
	</form>

	<div class="mt-6"><TagFilter /></div>
	{#if data.journeys.length === 0}
		<p class="mt-6 text-stone-600">{m.journeys_empty()}</p>
	{:else}
		<ul
			class="mt-6 divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="journey-list"
		>
			{#each journeys as j (j.id)}
				<!-- The title's link covers the row; the tags link above it. -->
				<li class="relative flex items-center gap-4 px-4 py-3 hover:bg-stone-50">
					<span class="flex flex-1 flex-col gap-1">
						<a
							href={resolve('/journeys/[id]', { id: j.id })}
							class="font-medium after:absolute after:inset-0">{j.title}</a
						>
						<TagChips tags={j.tags} href={byTag} />
					</span>
					<span class="text-sm text-stone-600"
						>{m.journey_stages_count({ done: j.stages_done, total: j.stages })}</span
					>
					<span class="w-20 text-sm text-stone-600 tabular-nums"
						>{formatDistance(j.distance_m)}</span
					>
					<span class="w-24 text-sm text-stone-600 tabular-nums"
						>{formatDuration(j.duration_s)}</span
					>
					<!-- Above the title's link. -->
					{#if confirming === j.id}
						<button
							type="button"
							class="relative rounded bg-red-700 px-2 py-1 text-xs text-white"
							data-testid="journey-list-delete-confirm"
							onclick={() => remove(j.id)}>{m.journey_delete_confirm()}</button
						>
					{:else}
						<button
							type="button"
							disabled={!hydrated.value}
							class="relative text-xs text-stone-500 underline hover:text-red-700"
							data-testid="journey-list-delete"
							onclick={() => (confirming = j.id)}>{m.route_delete()}</button
						>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	{#if shared.length > 0}
		<h2 class="mt-8 mb-2 text-lg font-semibold">{m.shared_title()}</h2>
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="shared-journeys"
		>
			{#each shared as j (j.id)}
				<li class="flex items-center gap-4 px-4 py-3">
					<a
						href={resolve('/journeys/[id]', { id: j.id })}
						class="flex-1 font-medium hover:underline">{j.title}</a
					>
					<span class="text-sm text-stone-600">{m.shared_by({ user: j.owner_username })}</span>
					<span class="text-sm text-stone-600"
						>{m.journey_stages_count({ done: j.stages_done, total: j.stages })}</span
					>
					<span class="w-28 text-xs text-stone-500"
						>{j.role === 'editor' ? m.role_editor() : m.role_viewer()}</span
					>
					<button type="button" class="text-xs text-stone-500 underline" onclick={() => leave(j.id)}
						>{m.shared_leave()}</button
					>
				</li>
			{/each}
		</ul>
	{/if}
</main>
