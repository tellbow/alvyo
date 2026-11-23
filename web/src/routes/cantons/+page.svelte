<script lang="ts">
	import { resolve } from '$app/paths';
	import { cantonName } from '#lib/cantons.js';
	import { getLocale } from '#lib/paraglide/runtime.js';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const cantons = $derived(
		data.cantons
			.map((c) => ({ ...c, name: cantonName(c.code, getLocale()) }))
			.sort((a, b) => a.name.localeCompare(b.name, getLocale()))
	);
</script>

<Seo title={m.cantons_title()} description={m.cantons_description()} />

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.cantons_title()}</h1>
	<p class="mt-1 text-stone-600">{m.cantons_description()}</p>
	<ul class="mt-6 grid gap-2 sm:grid-cols-2 md:grid-cols-3" data-testid="cantons">
		{#each cantons as c (c.code)}
			<li>
				<a
					href={resolve('/cantons/[code]', { code: c.code.toLowerCase() })}
					class="flex items-center justify-between gap-2 rounded-xl border border-stone-200 bg-surface px-4 py-3 font-medium hover:border-stone-300 hover:bg-stone-50"
				>
					<span class="truncate">{c.name}</span>
					<span class="shrink-0 text-sm text-stone-600 tabular-nums">{c.items}</span>
				</a>
			</li>
		{/each}
	</ul>
</main>
