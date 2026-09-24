<script lang="ts">
	import { page } from '$app/state';
	import {
		baseLocale,
		deLocalizeUrl,
		getLocale,
		locales,
		localizeUrl,
		type Locale
	} from '$lib/paraglide/runtime';

	/**
	 * Title, description and link-preview tags of a page. Pages that are not
	 * public (accounts, planning, private or unlisted items) pass
	 * `index={false}`: search engines leave them out.
	 */
	let {
		title,
		description,
		image,
		index = true
	}: { title: string; description?: string; image?: string; index?: boolean } = $props();

	// Share links (?t=) and filters never become the address search engines
	// show: one address per page and language (German without prefix).
	const path = $derived(deLocalizeUrl(new URL(page.url.pathname, page.url.origin)));
	const inLocale = (locale: Locale) => localizeUrl(path, { locale }).href;
	const url = $derived(inLocale(getLocale()));
	const OG_LOCALE: Record<Locale, string> = { de: 'de_CH', en: 'en_GB', fr: 'fr_CH', it: 'it_CH' };
	const shown = $derived(index && !page.url.searchParams.has('t'));
	const text = $derived(description && shorten(description.replace(/\s+/g, ' ').trim(), 200));

	function shorten(s: string, max: number) {
		if (s.length <= max) return s;
		const cut = s.lastIndexOf(' ', max - 2);
		return s.slice(0, cut > 0 ? cut : max - 2) + ' …';
	}
</script>

<svelte:head>
	<title>{title.includes('odysgeh') ? title : `${title} · odysgeh`}</title>
	{#if text}<meta name="description" content={text} />{/if}
	{#if shown}
		<link rel="canonical" href={url} />
		{#each locales as locale (locale)}
			<link rel="alternate" hreflang={locale} href={inLocale(locale)} />
		{/each}
		<link rel="alternate" hreflang="x-default" href={inLocale(baseLocale)} />
	{:else}
		<meta name="robots" content="noindex" />
	{/if}
	<meta property="og:type" content="website" />
	<meta property="og:site_name" content="odysgeh" />
	<meta property="og:locale" content={OG_LOCALE[getLocale()]} />
	<meta property="og:title" content={title} />
	{#if text}<meta property="og:description" content={text} />{/if}
	<meta property="og:url" content={shown ? url : page.url.href} />
	{#if image}
		<meta property="og:image" content={image} />
		<meta property="og:image:width" content="1200" />
		<meta property="og:image:height" content="630" />
		<meta name="twitter:card" content="summary_large_image" />
	{:else}
		<meta name="twitter:card" content="summary" />
	{/if}
</svelte:head>
