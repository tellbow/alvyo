<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	const missing = $derived(page.status === 404);
</script>

<Seo title={missing ? m.error_not_found_title() : m.error_title()} index={false} />

<main class="mx-auto mt-16 flex w-full max-w-md flex-col gap-4 px-4" data-testid="error-page">
	<p class="font-display text-5xl font-bold text-stone-300 tabular-nums">{page.status}</p>
	<h1 class="text-2xl font-semibold">{missing ? m.error_not_found_title() : m.error_title()}</h1>
	<p class="text-stone-600">{missing ? m.error_not_found_text() : m.error_text()}</p>
	<div class="flex flex-wrap gap-3">
		<a
			href={resolve('/')}
			class="flex h-11 items-center rounded-md bg-accent px-5 font-semibold text-on-accent hover:bg-accent-hover"
			>{m.error_home()}</a
		>
		<a
			href={resolve('/discover')}
			class="flex h-11 items-center rounded-md border border-stone-300 px-5 font-medium hover:bg-stone-100"
			>{m.discover_title()}</a
		>
	</div>
</main>
