<script lang="ts">
	import { env } from '$env/dynamic/public';
	import AnalyticsChoice from '$lib/components/AnalyticsChoice.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';

	let { data } = $props();
	const contact = env.PUBLIC_CONTACT_EMAIL;
</script>

<Seo title={m.about_title()} description={m.about_intro()} />

<main class="mx-auto w-full max-w-2xl overflow-y-auto px-4 py-8 text-stone-800">
	<h1 class="text-2xl font-semibold">{m.about_title()}</h1>
	<p class="mt-3">{m.about_intro()}</p>

	<h2 class="mt-8 text-lg font-semibold">{m.about_data_title()}</h2>
	<p class="mt-2">{m.about_data()}</p>
	<p class="mt-2 text-sm text-stone-600">{m.about_safety()}</p>

	<h2 class="mt-8 text-lg font-semibold">{m.about_privacy_title()}</h2>
	<p class="mt-2">{m.about_privacy()}</p>
	<AnalyticsChoice />

	<h2 class="mt-8 text-lg font-semibold">{m.about_source_title()}</h2>
	<p class="mt-2">
		{m.about_source()}
		{#if data.version}
			<a href={data.version.source} class="text-accent-ink underline" data-testid="source-link"
				>{data.version.source}</a
			>
			<span class="text-sm text-stone-500"
				>({m.about_version({ version: data.version.version })})</span
			>
		{/if}
	</p>

	{#if contact}
		<h2 class="mt-8 text-lg font-semibold">{m.about_contact_title()}</h2>
		<p class="mt-2">{contact}</p>
	{/if}
</main>
