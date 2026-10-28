<script lang="ts">
	import { resolve } from '$app/paths';
	import { api } from '#lib/api/client.js';
	import type { components } from '#lib/api/schema.js';
	import { m } from '#lib/paraglide/messages.js';
	import { actionButton, mainAction } from '#lib/components/actions.js';
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
		const { data: page } = await api().GET('/feed', {
			params: { query: { before: next, activity: true } }
		});
		busy = false;
		if (!page) return;
		items = [...items, ...page.items];
		next = page.next;
	}

	type Item = components['schemas']['FeedItem'];
	const did = (it: Item) =>
		it.kind === 'hike'
			? m.feed_hiked()
			: it.kind === 'comment'
				? m.feed_commented()
				: it.kind === 'journey'
					? m.feed_published_journey()
					: m.feed_published_route();
	// A hike's day is the one hiked, not when it was marked.
	const when = (it: Item) =>
		day.format(new Date(it.done_on ? `${it.done_on}T12:00:00Z` : it.published_at));
	const initials = (name: string) =>
		name
			.split(/\s+/)
			.filter(Boolean)
			.slice(0, 2)
			.map((w) => w[0].toUpperCase())
			.join('');
</script>

<Seo title={m.feed_title()} index={false} />

<main class="mx-auto w-full max-w-2xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.feed_title()}</h1>
	<p class="mt-1 text-stone-600">{m.feed_intro()}</p>

	{#if items.length === 0}
		<div class="mt-6 rounded-xl border border-stone-200 bg-surface p-5">
			<p class="text-stone-600">{m.feed_empty()}</p>
			<div class="mt-3 flex flex-wrap gap-2 text-sm">
				<a href={resolve('/friends')} class={mainAction}>{m.feed_find_people()}</a>
				<a href={resolve('/discover')} class={actionButton}>{m.discover_title()}</a>
			</div>
		</div>
	{:else}
		<ul class="mt-6 flex flex-col gap-3" data-testid="feed">
			{#each items as it, i (i)}
				<li
					class="flex gap-3 rounded-xl border border-stone-200 bg-surface p-4"
					data-testid="feed-{it.kind}"
				>
					<div
						class="flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-soft font-display font-bold text-accent-ink"
						aria-hidden="true"
					>
						{initials(it.owner_name)}
					</div>
					<div class="min-w-0 flex-1">
						<p class="text-sm">
							<a
								href={resolve('/u/[username]', { username: it.owner_username })}
								class="font-semibold hover:underline">{it.owner_name}</a
							>
							{did(it)}
							<span class="text-stone-500">· {when(it)}</span>
						</p>
						{#if it.id}
							<a
								href={it.target === 'route'
									? resolve('/routes/[id]', { id: it.id })
									: resolve('/journeys/[id]', { id: it.id })}
								class="mt-0.5 block truncate font-semibold hover:text-accent-ink">{it.title}</a
							>
						{:else}
							<p class="mt-0.5 font-semibold text-stone-600">{m.feed_hike_private()}</p>
						{/if}
						{#if it.kind === 'comment'}
							<p class="mt-1 line-clamp-2 text-sm text-stone-600">«{it.excerpt}»</p>
						{:else}
							<p
								class="mt-1 flex flex-wrap items-center gap-x-2 text-[13px] text-stone-600 tabular-nums"
							>
								{#if it.target === 'journey'}<span>{m.collection_stages({ n: it.stages })}</span
									>·{/if}
								<span>{formatDistance(it.distance_m)}</span>·
								<span>{formatDuration(it.duration_s, pace)}</span>
								{#if it.sac_grade > 0}
									<span
										class="rounded px-1.5 py-0.5 text-xs font-semibold"
										style:background={sacBackground(it.sac_grade)}
										style:color={sacInk(it.sac_grade)}>{formatSAC(it.sac_grade, it.sac_max)}</span
									>
								{/if}
							</p>
						{/if}
					</div>
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
