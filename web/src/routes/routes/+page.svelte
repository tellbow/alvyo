<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { hikeDate } from '$lib/util/locale';
	import { sacBackground, sacInk } from '$lib/planner/colors';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '$lib/planner/route';
	import TagChips from '$lib/tags/TagChips.svelte';
	import TagFilter from '$lib/tags/TagFilter.svelte';
	import { hasTag } from '$lib/tags/tags';
	import { doneDate, passes, readDone } from '$lib/done/done';
	import DoneFilter from '$lib/done/DoneFilter.svelte';

	let { data } = $props();
	const pace = $derived(data.user?.speed_factor ?? 1);
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	const done = $derived(readDone(page.url.searchParams));
	// Deleted here, and the one asking «really?».
	let deleted = $state<string[]>([]);
	let confirming = $state<string>();
	const routes = $derived(
		data.routes.filter(
			(r) => hasTag(r.tags, tag) && passes(done, r.done_on) && !deleted.includes(r.id)
		)
	);
	const byTag = (t: string) => `?tag=${encodeURIComponent(t)}`;

	async function leave(id: string) {
		const { response } = await api().DELETE('/routes/{id}/access', { params: { path: { id } } });
		if (response.ok) shared = shared.filter((r) => r.id !== id);
	}

	async function remove(id: string) {
		const { response } = await api().DELETE('/routes/{id}', { params: { path: { id } } });
		if (response.ok) deleted = [...deleted, id];
		confirming = undefined;
	}
</script>

<Seo title={m.routes_title()} index={false} />

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<div class="mb-6 flex flex-wrap items-center justify-between gap-3">
		<h1 class="text-2xl font-semibold">{m.routes_title()}</h1>
		<div class="flex items-center gap-4">
			<a href={resolve('/routes/map')} class="text-sm hover:text-accent-ink">{m.mymap_link()}</a>
			<a href={resolve('/import')} class="text-sm hover:text-accent-ink">{m.import_link()}</a>
			<a
				href={resolve('/plan')}
				class="rounded-md bg-accent px-3 py-1.5 text-sm text-on-accent hover:bg-accent-hover"
			>
				{m.route_new()}
			</a>
		</div>
	</div>
	<TagFilter />
	{#if data.routes.length > 0}<DoneFilter />{/if}
	{#if data.routes.length === 0}
		<p class="text-stone-600">{m.routes_empty()}</p>
	{:else if routes.length === 0}
		<p class="text-stone-600">{m.done_filter_none()}</p>
	{:else}
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="route-list"
		>
			{#each routes as r (r.id)}
				<!-- The title's link covers the row; the tags link above it. -->
				<li
					class="relative flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 hover:bg-stone-50"
				>
					<span class="flex w-full min-w-0 flex-col gap-1 sm:w-auto sm:flex-1">
						<a
							href={resolve('/routes/[id]', { id: r.id })}
							class="font-medium after:absolute after:inset-0">{r.title}</a
						>
						{#if r.hike}
							<span class="text-xs text-stone-500" data-testid="hiked"
								>{m.routes_hiked({ date: hikeDate(r.hike.at) })}</span
							>
						{:else if r.done_on}
							<span class="text-xs text-stone-500" data-testid="done-on"
								>✓ {m.done_on({ date: doneDate(r.done_on) })}</span
							>
						{/if}
						<TagChips tags={r.tags} href={byTag} />
					</span>
					<span class="text-sm text-stone-600 tabular-nums"
						>{formatDistance(r.totals.distance_m)}</span
					>
					<span class="text-sm text-stone-600 tabular-nums sm:w-24"
						>{formatDuration(r.totals.duration_s, pace)}</span
					>
					<span class="text-sm text-stone-600 tabular-nums sm:w-20"
						>↑&nbsp;{formatHeight(r.totals.ascent_m)}</span
					>
					<span
						class="w-16 rounded px-1.5 py-0.5 text-center text-xs font-semibold"
						style:background={sacBackground(r.totals.sac_grade)}
						style:color={sacInk(r.totals.sac_grade)}
					>
						{formatSAC(r.totals.sac_grade, r.totals.sac_max)}
					</span>
					<span class="text-xs text-stone-500 sm:w-20 sm:text-right">
						{r.visibility === 'public' ? m.visibility_public() : m.visibility_private()}
					</span>
					<!-- Above the title's link. -->
					{#if confirming === r.id}
						<button
							type="button"
							class="relative ml-auto rounded bg-red-700 px-2 py-1 text-xs text-white sm:ml-0"
							data-testid="route-list-delete-confirm"
							onclick={() => remove(r.id)}>{m.route_delete_confirm()}</button
						>
					{:else}
						<button
							type="button"
							class="relative ml-auto text-xs text-stone-500 underline hover:text-red-700 sm:ml-0"
							data-testid="route-list-delete"
							onclick={() => (confirming = r.id)}>{m.route_delete()}</button
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
			data-testid="shared-routes"
		>
			{#each shared.filter((r) => passes(done, r.done_on)) as r (r.id)}
				<li class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3">
					<a
						href={resolve('/routes/[id]', { id: r.id })}
						class="w-full font-medium hover:underline sm:w-auto sm:flex-1">{r.title}</a
					>
					<span class="text-sm text-stone-600">{m.shared_by({ user: r.owner_username })}</span>
					<span class="text-sm text-stone-600 tabular-nums"
						>{formatDistance(r.totals.distance_m)}</span
					>
					<span class="text-xs text-stone-500 sm:w-28"
						>{r.role === 'editor' ? m.role_editor() : m.role_viewer()}</span
					>
					<button type="button" class="text-xs text-stone-500 underline" onclick={() => leave(r.id)}
						>{m.shared_leave()}</button
					>
				</li>
			{/each}
		</ul>
	{/if}
</main>
