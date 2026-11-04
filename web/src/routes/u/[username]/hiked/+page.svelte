<script lang="ts">
	import { resolve } from '$app/paths';
	import Achievements from '#lib/hiked/Achievements.svelte';
	import HikedMap from '#lib/hiked/HikedMap.svelte';
	import HikedStats from '#lib/hiked/HikedStats.svelte';
	import { chip } from '#lib/hiked/hiked.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const shared = $derived(data.shared);
	const title = $derived(m.hiked_by({ name: shared.display_name }));
	// The map stays whole: which line is of which year is not shared.
	const items = $derived(shared.lines?.map((l) => ({ lines: [l] })) ?? []);

	let year = $state<number>();
	const totals = $derived(
		year ? shared.years?.find((y) => y.year === year) : (shared.total ?? undefined)
	);
</script>

<Seo {title} index={false} />

<main class="flex min-h-0 flex-1 flex-col md:flex-row">
	{#if items.length}
		<section class="relative h-[50dvh] shrink-0 md:h-auto md:flex-1 md:shrink">
			<HikedMap {items} />
		</section>
	{/if}

	<aside
		class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto border-t border-stone-200 bg-surface p-4 md:border-t-0 {items.length
			? 'md:w-96 md:flex-none md:border-l'
			: 'mx-auto w-full max-w-xl'}"
		data-testid="shared-hiked"
	>
		<div class="flex items-baseline justify-between gap-3">
			<h1 class="text-xl font-semibold">{title}</h1>
			<a
				href={resolve('/u/[username]', { username: shared.username })}
				class="text-sm text-accent-ink underline">@{shared.username}</a
			>
		</div>
		{#if items.length}
			<p class="text-sm text-stone-500">{m.hiked_shared_map()}</p>
		{/if}

		{#if shared.years?.length}
			<div class="flex flex-wrap gap-2" role="group" aria-label={m.hiked_years()}>
				<button
					type="button"
					class={chip(!year)}
					aria-pressed={!year}
					onclick={() => (year = undefined)}>{m.hiked_all()}</button
				>
				{#each shared.years as y (y.year)}
					<button
						type="button"
						class={chip(year === y.year)}
						aria-pressed={year === y.year}
						onclick={() => (year = y.year)}>{y.year}</button
					>
				{/each}
			</div>
		{/if}
		{#if totals}
			<HikedStats {totals} />
		{/if}
		{#if shared.achievements}
			<Achievements achievements={shared.achievements} />
		{/if}
	</aside>
</main>
