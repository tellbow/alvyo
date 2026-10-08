<script lang="ts">
	import { primaryButton, primaryButtonSmall } from '$lib/components/actions';
	import { focused } from '$lib/util/focus';
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
	import { doneDate, passes, readDone } from '$lib/done/done';
	import DoneFilter from '$lib/done/DoneFilter.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	let { data } = $props();
	const hydrated = new Hydrated();
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	const done = $derived(readDone(page.url.searchParams));
	// Deleted here, and the one asking «really?».
	let deleted = $state<string[]>([]);
	let confirming = $state<string>();
	const journeys = $derived(
		data.journeys.filter(
			(j) => hasTag(j.tags, tag) && passes(done, j.done_on) && !deleted.includes(j.id)
		)
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
		class="{primaryButtonSmall} mt-4 inline-block"
		data-testid="journey-plan-link">{m.jplan_link()}</a
	>

	<form method="post" onsubmit={create} class="mt-6 flex gap-2">
		<input
			bind:value={title}
			required
			maxlength="120"
			placeholder={m.journey_new()}
			aria-label={m.field_title()}
			class="flex-1 rounded-md border border-stone-400 px-3 py-2"
		/>
		<button disabled={!hydrated.value} class={primaryButton}>
			{m.journey_create()}
		</button>
	</form>

	<div class="mt-6"><TagFilter /></div>
	{#if data.journeys.length > 0}<DoneFilter />{/if}
	{#if data.journeys.length === 0}
		<p class="mt-6 text-stone-600">{m.journeys_empty()}</p>
	{:else if journeys.length === 0}
		<p class="text-stone-600">{m.done_filter_none()}</p>
	{:else}
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="journey-list"
		>
			{#each journeys as j (j.id)}
				<!-- The title's link covers the row; the tags link above it. -->
				<li
					class="relative flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 hover:bg-stone-50"
				>
					<span class="flex w-full min-w-0 flex-col gap-1 sm:w-auto sm:flex-1">
						<a
							href={resolve('/journeys/[id]', { id: j.id })}
							class="font-medium after:absolute after:inset-0">{j.title}</a
						>
						{#if j.done_on}
							<span class="text-xs text-stone-500" data-testid="done-on"
								>✓ {m.done_on({ date: doneDate(j.done_on) })}</span
							>
						{/if}
						<TagChips tags={j.tags} href={byTag} />
					</span>
					<span class="text-sm text-stone-600"
						>{m.journey_stages_count({ done: j.stages_done, total: j.stages })}</span
					>
					<span class="text-sm text-stone-600 tabular-nums sm:w-20"
						>{formatDistance(j.distance_m)}</span
					>
					<span class="text-sm text-stone-600 tabular-nums sm:w-24"
						>{formatDuration(j.duration_s)}</span
					>
					<!-- Above the title's link. -->
					{#if confirming === j.id}
						<button
							type="button"
							class="relative ml-auto rounded bg-red-700 px-2 py-1 text-xs text-white sm:ml-0"
							use:focused
							data-testid="journey-list-delete-confirm"
							onclick={() => remove(j.id)}>{m.journey_delete_confirm()}</button
						>
					{:else}
						<button
							type="button"
							disabled={!hydrated.value}
							class="relative ml-auto text-xs text-stone-500 underline hover:text-red-700 sm:ml-0 dark:hover:text-red-400 pointer-coarse:py-2"
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
			{#each shared.filter((j) => passes(done, j.done_on)) as j (j.id)}
				<li class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3">
					<a
						href={resolve('/journeys/[id]', { id: j.id })}
						class="w-full font-medium hover:underline sm:w-auto sm:flex-1">{j.title}</a
					>
					<span class="text-sm text-stone-600">{m.shared_by({ user: j.owner_username })}</span>
					<span class="text-sm text-stone-600"
						>{m.journey_stages_count({ done: j.stages_done, total: j.stages })}</span
					>
					<span class="text-xs text-stone-500 sm:w-28"
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
