<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { hikeDate } from '$lib/util/locale';
	import { SAC_COLOR } from '$lib/planner/colors';
	import { formatDistance, formatDuration, formatSAC } from '$lib/planner/route';
	import TagChips from '$lib/tags/TagChips.svelte';
	import TagFilter from '$lib/tags/TagFilter.svelte';
	import { hasTag } from '$lib/tags/tags';

	let { data } = $props();
	const pace = $derived(data.user?.speed_factor ?? 1);
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	const routes = $derived(data.routes.filter((r) => hasTag(r.tags, tag)));
	const byTag = (t: string) => `?tag=${encodeURIComponent(t)}`;

	async function leave(id: string) {
		const { response } = await api().DELETE('/routes/{id}/access', { params: { path: { id } } });
		if (response.ok) shared = shared.filter((r) => r.id !== id);
	}
</script>

<Seo title={m.routes_title()} index={false} />

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<div class="mb-6 flex items-center justify-between">
		<h1 class="text-2xl font-semibold">{m.routes_title()}</h1>
		<div class="flex items-center gap-4">
			<a href={resolve('/routes/map')} class="text-sm hover:text-emerald-700">{m.mymap_link()}</a>
			<a href={resolve('/import')} class="text-sm hover:text-emerald-700">{m.import_link()}</a>
			<a
				href={resolve('/plan')}
				class="rounded-md bg-emerald-700 px-3 py-1.5 text-sm text-white hover:bg-emerald-800"
			>
				{m.route_new()}
			</a>
		</div>
	</div>
	<TagFilter />
	{#if data.routes.length === 0}
		<p class="text-stone-600">{m.routes_empty()}</p>
	{:else}
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-white"
			data-testid="route-list"
		>
			{#each routes as r (r.id)}
				<!-- The title's link covers the row; the tags link above it. -->
				<li class="relative flex items-center gap-4 px-4 py-3 hover:bg-stone-50">
					<span class="flex flex-1 flex-col gap-1">
						<a
							href={resolve('/routes/[id]', { id: r.id })}
							class="font-medium after:absolute after:inset-0">{r.title}</a
						>
						{#if r.hike}
							<span class="text-xs text-stone-500" data-testid="hiked"
								>{m.routes_hiked({ date: hikeDate(r.hike.at) })}</span
							>
						{/if}
						<TagChips tags={r.tags} href={byTag} />
					</span>
					<span class="text-sm text-stone-600 tabular-nums"
						>{formatDistance(r.totals.distance_m)}</span
					>
					<span class="w-24 text-sm text-stone-600 tabular-nums"
						>{formatDuration(r.totals.duration_s, pace)}</span
					>
					<span class="w-20 text-sm text-stone-600 tabular-nums"
						>↑ {Math.round(r.totals.ascent_m)} m</span
					>
					<span
						class="w-16 rounded px-1.5 py-0.5 text-center text-xs font-semibold text-white"
						style:background={SAC_COLOR[`T${r.totals.sac_grade}`] ?? '#a8a29e'}
					>
						{formatSAC(r.totals.sac_grade, r.totals.sac_max)}
					</span>
					<span class="w-20 text-right text-xs text-stone-500">
						{r.visibility === 'public' ? m.visibility_public() : m.visibility_private()}
					</span>
				</li>
			{/each}
		</ul>
	{/if}

	{#if shared.length > 0}
		<h2 class="mt-8 mb-2 text-lg font-semibold">{m.shared_title()}</h2>
		<ul
			class="divide-y divide-stone-200 rounded-md border border-stone-200 bg-white"
			data-testid="shared-routes"
		>
			{#each shared as r (r.id)}
				<li class="flex items-center gap-4 px-4 py-3">
					<a href={resolve('/routes/[id]', { id: r.id })} class="flex-1 font-medium hover:underline"
						>{r.title}</a
					>
					<span class="text-sm text-stone-600">{m.shared_by({ user: r.owner_username })}</span>
					<span class="text-sm text-stone-600 tabular-nums"
						>{formatDistance(r.totals.distance_m)}</span
					>
					<span class="w-28 text-xs text-stone-500"
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
