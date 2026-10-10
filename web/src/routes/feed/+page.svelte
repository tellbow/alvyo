<script lang="ts">
	import { resolve } from '$app/paths';
	import { api } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { intlLocale } from '#lib/util/locale.js';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatSAC } from '#lib/planner/route.js';

	let { data } = $props();
	// svelte-ignore state_referenced_locally
	let items = $state(data.items);
	// svelte-ignore state_referenced_locally
	let next = $state(data.next);
	let busy = $state(false);
	const pace = $derived(data.user?.speed_factor ?? 1);
	const day = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			dateStyle: 'medium',
			timeZone: 'Europe/Zurich'
		})
	);

	async function more() {
		busy = true;
		const { data: page } = await api().GET('/feed', { params: { query: { before: next } } });
		busy = false;
		if (!page) return;
		items = [...items, ...page.items];
		next = page.next;
	}
</script>

<Seo title={m.feed_title()} index={false} />

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.feed_title()}</h1>
	<p class="mt-1 text-stone-600">{m.feed_intro()}</p>

	{#if items.length === 0}
		<p class="mt-6 text-stone-600">
			{m.feed_empty()}
			<a href={resolve('/discover')} class="underline">{m.discover_title()}</a>
		</p>
	{:else}
		<ul
			class="mt-6 divide-y divide-stone-200 rounded-md border border-stone-200 bg-surface"
			data-testid="feed"
		>
			{#each items as it (it.id)}
				<li class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3">
					<div class="min-w-0 flex-1">
						<a
							href={it.kind === 'route'
								? resolve('/routes/[id]', { id: it.id })
								: resolve('/journeys/[id]', { id: it.id })}
							class="font-medium hover:underline">{it.title}</a
						>
						<p class="text-xs text-stone-500">
							<a
								href={resolve('/u/[username]', { username: it.owner_username })}
								class="hover:underline">{it.owner_name}</a
							>
							· {day.format(new Date(it.published_at))}
							· {it.kind === 'route'
								? m.collection_kind_route()
								: m.collection_stages({ n: it.stages })}
						</p>
					</div>
					<span class="text-sm text-stone-600 tabular-nums">{formatDistance(it.distance_m)}</span>
					<span class="w-24 text-sm text-stone-600 tabular-nums"
						>{formatDuration(it.duration_s, pace)}</span
					>
					{#if it.sac_grade > 0}
						<span
							class="rounded px-1.5 py-0.5 text-xs font-semibold"
							style:background={sacBackground(it.sac_grade)}
							style:color={sacInk(it.sac_grade)}>{formatSAC(it.sac_grade, it.sac_max)}</span
						>
					{/if}
				</li>
			{/each}
		</ul>
		{#if next}
			<button type="button" class="mt-3 text-sm underline" disabled={busy} onclick={more}
				>{m.feed_more()}</button
			>
		{/if}
	{/if}
</main>
