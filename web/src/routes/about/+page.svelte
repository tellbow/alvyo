<script lang="ts">
	import { PUBLIC_CONTACT_EMAIL } from '$app/env/public';
	import AnalyticsChoice from '#lib/components/AnalyticsChoice.svelte';
	import { releases } from '#lib/news/releases.js';
	import { m } from '#lib/paraglide/messages.js';
	import { intlLocale } from '#lib/util/locale.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const contact = PUBLIC_CONTACT_EMAIL;
	const day = (iso: string) =>
		new Intl.DateTimeFormat(intlLocale(), { dateStyle: 'medium', timeZone: 'UTC' }).format(
			new Date(`${iso}T00:00:00Z`)
		);
</script>

<Seo title={m.about_title()} description={m.about_intro()} />

<main class="mx-auto w-full max-w-2xl overflow-y-auto px-4 py-8 text-stone-800">
	<h1 class="text-2xl font-semibold">{m.about_title()}</h1>
	<p class="mt-3">{m.about_intro()}</p>

	<h2 class="mt-8 text-lg font-semibold" id="news">{m.about_news_title()}</h2>
	<ul class="mt-2 flex flex-col gap-3" data-testid="news">
		{#each releases as r (r.version)}
			<li>
				<p class="text-sm text-stone-600">{r.version} · {day(r.date)}</p>
				<p>{r.text()}</p>
			</li>
		{/each}
	</ul>

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
