<script lang="ts">
	import {
		PUBLIC_CONTACT_EMAIL,
		PUBLIC_OPERATOR_ADDRESS,
		PUBLIC_OPERATOR_NAME
	} from '$app/env/public';
	import { sources } from '#lib/about/sources.js';
	import AnalyticsChoice from '#lib/components/AnalyticsChoice.svelte';
	import { releases } from '#lib/news/releases.js';
	import { m } from '#lib/paraglide/messages.js';
	import { intlLocale } from '#lib/util/locale.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const contact = PUBLIC_CONTACT_EMAIL;
	const operator = PUBLIC_OPERATOR_NAME;
	const address = PUBLIC_OPERATOR_ADDRESS;
	const day = (iso: string) =>
		new Intl.DateTimeFormat(intlLocale(), { dateStyle: 'medium', timeZone: 'UTC' }).format(
			new Date(`${iso}T00:00:00Z`)
		);
	// Third-party licences of exactly this version (a git SHA or tag; main for dev builds).
	const notice = $derived.by(() => {
		if (!data.version) return '';
		const ref = data.version.version === 'dev' ? 'main' : data.version.version;
		return `${data.version.source}/blob/${ref}/NOTICE`;
	});
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

	<h2 class="mt-8 text-lg font-semibold" id="data">{m.about_data_title()}</h2>
	<p class="mt-2">{m.about_data_intro()}</p>
	<ul class="mt-2 flex list-inside list-disc flex-col gap-1" data-testid="data-sources">
		{#each sources as s (s.text)}
			<li>
				{s.text()}{#if s.terms}&nbsp;(<a
						href={s.terms.href}
						class="text-accent-ink underline"
						rel="noopener">{s.terms.label}</a
					>){/if}
			</li>
		{/each}
	</ul>
	<p class="mt-2 text-sm text-stone-600">{m.about_safety()}</p>

	<h2 class="mt-8 text-lg font-semibold" id="privacy">{m.about_privacy_title()}</h2>
	<p class="mt-2">{m.about_privacy()}</p>
	<p class="mt-2">{m.about_privacy_services()}</p>
	<p class="mt-2">{m.about_privacy_app()}</p>
	<p class="mt-2">{m.about_privacy_rights()}</p>
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
	{#if data.version}
		<p class="mt-2">
			{m.about_notice()}
			<a href={notice} class="text-accent-ink underline" data-testid="notice-link">NOTICE</a>
		</p>
	{/if}

	{#if operator}
		<h2 class="mt-8 text-lg font-semibold" id="operator">{m.about_operator_title()}</h2>
		<p class="mt-2">{m.about_operator()}</p>
		<p class="mt-1" data-testid="operator">
			{operator}{#if address}<br />{address}{/if}{#if contact}<br />{contact}{/if}
		</p>
	{:else if contact}
		<h2 class="mt-8 text-lg font-semibold">{m.about_contact_title()}</h2>
		<p class="mt-2">{contact}</p>
	{/if}
</main>
