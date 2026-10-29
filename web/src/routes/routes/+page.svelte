<script lang="ts">
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { hikeDate } from '#lib/util/locale.js';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';
	import TagChips from '#lib/tags/TagChips.svelte';
	import TagFilter from '#lib/tags/TagFilter.svelte';
	import { hasTag } from '#lib/tags/tags.js';
	import { doneDate, passes, readDone } from '#lib/done/done.js';
	import DoneFilter from '#lib/done/DoneFilter.svelte';
	import RowMenu from '#lib/lists/RowMenu.svelte';
	import VisibilityBadge from '#lib/lists/VisibilityBadge.svelte';

	let { data } = $props();
	const pace = $derived(data.user?.speed_factor ?? 1);
	// svelte-ignore state_referenced_locally
	let shared = $state(data.shared);
	const tag = $derived(page.url.searchParams.get('tag'));
	const done = $derived(readDone(page.url.searchParams));
	let deleted = $state<string[]>([]);
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
	}
</script>

<Seo title={m.routes_title()} index={false} />

<main class="mx-auto w-full max-w-4xl flex-1 overflow-y-auto px-4 py-8">
	<div class="mb-6 flex flex-wrap items-center justify-between gap-3">
		<h1 class="text-2xl font-semibold">{m.routes_title()}</h1>
		<div class="flex items-center gap-4">
			<a href={resolve('/routes/map')} class="text-sm hover:text-accent-ink">{m.mymap_link()}</a>
			<a href={resolve('/import')} class="text-sm hover:text-accent-ink">{m.import_link()}</a>
			<a href={resolve('/plan')} class={primaryButtonSmall}>
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
		<div class="rounded-md border border-stone-200 bg-surface">
			<div
				class="hidden gap-x-4 border-b border-stone-200 px-4 py-2 text-xs font-medium text-stone-500 sm:flex"
				aria-hidden="true"
			>
				<span class="flex-1">{m.field_title()}</span>
				<span class="w-20">{m.stat_distance()}</span>
				<span class="w-24">{m.stat_time()}</span>
				<span class="w-20">{m.stat_ascent()}</span>
				<span class="w-16 text-center">{m.stat_sac()}</span>
				<span class="w-28">{m.field_visibility()}</span>
				<span class="w-9"></span>
			</div>
			<ul class="divide-y divide-stone-200" data-testid="route-list">
				{#each routes as r (r.id)}
					<!-- The title's link covers the row; the tags link above it. -->
					<li
						class="relative flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 hover:bg-stone-50"
					>
						<span class="flex w-full min-w-0 flex-col gap-1 pr-8 sm:w-auto sm:flex-1 sm:pr-0">
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
						<span class="text-sm text-stone-600 tabular-nums sm:w-20"
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
						<span class="sm:w-28"><VisibilityBadge visibility={r.visibility} /></span>
						<span class="absolute top-2 right-2 sm:static">
							<RowMenu
								testid="route-row"
								title={r.title}
								confirm={m.route_delete_confirm()}
								onremove={() => remove(r.id)}
							/>
						</span>
					</li>
				{/each}
			</ul>
		</div>
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
					<span class="sm:w-28"><VisibilityBadge role={r.role} owner={r.owner_username} /></span>
					<span class="ml-auto sm:ml-0">
						<RowMenu testid="shared-row" title={r.title} leave onremove={() => leave(r.id)} />
					</span>
				</li>
			{/each}
		</ul>
	{/if}
</main>
