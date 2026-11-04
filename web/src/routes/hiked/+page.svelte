<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import type { HikedItem } from '#lib/api/client.js';
	import { doneDate } from '#lib/done/done.js';
	import Achievements from '#lib/hiked/Achievements.svelte';
	import HikedMap from '#lib/hiked/HikedMap.svelte';
	import HikedStats from '#lib/hiked/HikedStats.svelte';
	import { chip } from '#lib/hiked/hiked.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatDistance, formatHeight } from '#lib/planner/route.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();

	const items = $derived(data.hiked?.items ?? []);
	const totals = $derived(
		data.year ? data.hiked?.years?.find((y) => y.year === data.year) : data.hiked?.total
	);
	const href = (it: HikedItem) =>
		it.kind === 'journey'
			? resolve('/journeys/[id]', { id: it.id })
			: resolve('/routes/[id]', { id: it.id });
	const yearHref = (year?: number) => `${resolve('/hiked')}${year ? `?year=${year}` : ''}`;
</script>

<Seo title={m.hiked_title()} index={false} />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
		<HikedMap {items} onclick={(i) => goto(href(items[i]))} />
	</section>

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:w-96 md:flex-none md:border-t-0 md:border-l"
		data-testid="hiked-panel"
	>
		<div class="flex items-baseline justify-between">
			<h1 class="text-xl font-semibold">{m.hiked_title()}</h1>
			<a href={resolve('/routes')} class="text-sm text-accent-ink underline">{m.routes_title()}</a>
		</div>
		<p class="text-sm text-stone-500">
			{m.hiked_private()}
			<a href={resolve('/account')} class="text-accent-ink underline">{m.hiked_share()}</a>
		</p>

		{#if !data.hiked}
			<p role="alert" class="text-sm text-red-700 dark:text-red-400">{m.error_generic()}</p>
		{:else if !data.hiked.years?.length}
			<p data-testid="hiked-empty">{m.hiked_empty()}</p>
		{:else}
			<nav class="flex flex-wrap gap-2" aria-label={m.hiked_years()}>
				<a
					href={yearHref()}
					data-sveltekit-noscroll
					class={chip(!data.year)}
					aria-current={!data.year ? 'page' : undefined}>{m.hiked_all()}</a
				>
				{#each data.hiked.years as y (y.year)}
					<a
						href={yearHref(y.year)}
						data-sveltekit-noscroll
						class={chip(data.year === y.year)}
						aria-current={data.year === y.year ? 'page' : undefined}
						data-testid="hiked-year">{y.year}</a
					>
				{/each}
			</nav>

			{#if totals}
				<HikedStats {totals} />
			{/if}
			{#if data.achievements}
				<Achievements achievements={data.achievements} />
			{/if}

			<ul class="flex flex-col divide-y divide-stone-200">
				{#each items as it, i (`${it.kind}-${it.id}-${it.on}-${i}`)}
					<li data-testid="hiked-item">
						<a href={href(it)} class="block py-2 hover:text-accent-ink">
							<span class="block font-medium">{it.title}</span>
							<span class="block text-sm text-stone-500">
								{doneDate(it.on)} · {formatDistance(it.distance_m)} · ↑&nbsp;{formatHeight(
									it.ascent_m
								)}
							</span>
						</a>
					</li>
				{/each}
			</ul>
		{/if}
	</aside>
</main>
