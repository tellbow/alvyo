<script lang="ts">
	import BugReport from '$lib/bugs/BugReport.svelte';
	import './layout.css';
	import { afterNavigate, goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { choose } from '$lib/util/choose';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { parseTheme, setTheme, themes, type Theme } from '$lib/util/theme';
	import {
		deLocalizeUrl,
		getLocale,
		locales,
		setLocale,
		type Locale
	} from '$lib/paraglide/runtime';

	let { data, children } = $props();
	let resent = $state(false);

	async function logout() {
		await api().POST('/auth/logout');
		await invalidateAll();
		await goto(resolve('/'));
	}

	const hydrated = new Hydrated();
	const languages: Record<Locale, string> = {
		de: 'Deutsch',
		en: 'English',
		fr: 'Français',
		it: 'Italiano'
	};

	// Remembered in a cookie; for accounts also the language of e-mails.
	async function language(l: Locale) {
		if (data.user) await api().PATCH('/me', { body: { locale: l } });
		await setLocale(l);
	}

	const themeNames: Record<Theme, () => string> = {
		system: m.theme_system,
		light: m.theme_light,
		dark: m.theme_dark
	};

	// The page's section in the navigation, whatever the language prefix.
	const here = $derived(deLocalizeUrl(page.url).pathname);
	function tab(section: string) {
		const on = here === section || here.startsWith(section + '/');
		return `rounded-full px-3.5 py-1.5 ${on ? 'bg-stone-900 text-stone-50 dark:bg-stone-200 dark:text-stone-900' : 'hover:text-accent-ink'}`;
	}

	// Below xl the links and settings go into a menu.
	let menu = $state(false);
	afterNavigate(() => (menu = false));

	async function resend() {
		const { response } = await api().POST('/auth/verify-email/resend');
		resent = response.ok;
	}
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && (menu = false)} />

{#snippet links()}
	<a href={resolve('/discover')} class={tab('/discover')}>{m.nav_discover()}</a>
	<a href={resolve('/plan')} class={tab('/plan')}>{m.nav_plan()}</a>
	{#if data.user}
		<a href={resolve('/feed')} class={tab('/feed')}>{m.nav_feed()}</a>
		<a href={resolve('/routes')} class={tab('/routes')}>{m.nav_routes()}</a>
		<a href={resolve('/journeys')} class={tab('/journeys')}>{m.nav_journeys()}</a>
		<a href={resolve('/collections')} class={tab('/collections')}>{m.nav_collections()}</a>
		{#if data.user.role !== 'user'}
			<a href={resolve('/moderation')} class={tab('/moderation')}>{m.nav_moderation()}</a>
		{/if}
	{/if}
	<a href={resolve('/about')} class={tab('/about')}>{m.nav_about()}</a>
{/snippet}

{#snippet settings()}
	<select
		class="rounded-full border-0 bg-transparent py-0.5 text-stone-600"
		aria-label={m.nav_language()}
		value={getLocale()}
		disabled={!hydrated.value}
		use:choose={(v) => language(v as Locale)}
		data-testid="language"
	>
		{#each locales as l (l)}
			<option value={l}>{languages[l]}</option>
		{/each}
	</select>
	<select
		class="rounded-full border-0 bg-transparent py-0.5 text-stone-600"
		aria-label={m.nav_theme()}
		value={data.theme}
		disabled={!hydrated.value}
		use:choose={(v) => setTheme(parseTheme(v))}
		data-testid="theme"
	>
		{#each themes as t (t)}
			<option value={t}>{themeNames[t]()}</option>
		{/each}
	</select>
{/snippet}

{#snippet account()}
	{#if data.user}
		<a href={resolve('/friends')} class="hover:text-accent-ink" data-testid="nav-friends">
			{m.nav_friends()}{#if data.user.friend_requests > 0}<span
					class="ml-1 rounded-full bg-accent px-1.5 text-xs text-on-accent tabular-nums"
					title={m.friends_incoming()}>{data.user.friend_requests}</span
				>{/if}
		</a>
		<a
			href={resolve('/account')}
			class="text-stone-600 hover:text-accent-ink"
			data-testid="current-user"
		>
			{data.user.username}
		</a>
		<button type="button" onclick={logout} class="text-left hover:text-accent-ink"
			>{m.nav_logout()}</button
		>
	{:else}
		<a href={resolve('/login')} class="hover:text-accent-ink">{m.nav_login()}</a>
	{/if}
{/snippet}

{#snippet signup()}
	<a
		href={resolve('/signup')}
		class="flex h-10 shrink-0 items-center rounded-full bg-accent px-5 text-sm font-semibold text-on-accent hover:bg-accent-hover"
	>
		{m.nav_signup()}
	</a>
{/snippet}

<div class="flex h-dvh flex-col bg-ground text-stone-900 print:h-auto">
	<header
		class="relative flex items-center gap-6 border-b border-stone-200 px-4 py-2.5 xl:px-5 print:hidden"
	>
		<a
			href={resolve('/')}
			aria-label="Alvyo"
			class="flex items-baseline font-display text-[28px] leading-none font-bold tracking-[-0.04em]"
		>
			<svg width="20" height="19" viewBox="0 0 24 23" fill="none" aria-hidden="true">
				<path
					d="M2.3 23L12 2L21.7 23"
					stroke="currentColor"
					stroke-width="4"
					stroke-linejoin="round"
				/>
				<path d="M7.8 11H16.2" class="stroke-accent" stroke-width="3.2" />
			</svg><span>lvyo</span>
		</a>
		<nav
			class="hidden items-center gap-1 rounded-full border border-stone-200 bg-surface p-1 text-sm font-medium xl:flex"
		>
			{@render links()}
		</nav>
		<div class="ml-auto hidden items-center gap-4 text-sm font-medium xl:flex">
			{@render settings()}
			{@render account()}
			{#if !data.user}{@render signup()}{/if}
		</div>

		<!-- In the header, not over the page: it hid what was below it. -->
		{#if data.user}<BugReport />{/if}

		<div class="flex items-center gap-2 xl:hidden {data.user ? '' : 'ml-auto'}">
			{#if !data.user}{@render signup()}{/if}
			<button
				type="button"
				class="flex size-10 items-center justify-center rounded-full hover:bg-stone-100"
				aria-label={m.nav_menu()}
				aria-expanded={menu}
				aria-controls="menu"
				onclick={() => (menu = !menu)}
				data-testid="menu"
			>
				<svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden="true">
					<path
						d={menu ? 'M6 6l12 12M18 6L6 18' : 'M4 7h16M4 12h16M4 17h16'}
						stroke="currentColor"
						stroke-width="2"
						stroke-linecap="round"
					/>
				</svg>
			</button>
		</div>
		{#if menu}
			<div
				id="menu"
				class="absolute inset-x-0 top-full z-30 flex max-h-[calc(100dvh-4rem)] flex-col gap-4 overflow-y-auto overscroll-contain border-b border-stone-200 bg-surface p-4 shadow-lg xl:hidden"
			>
				<nav class="flex flex-col items-start gap-1 font-medium">
					{@render links()}
				</nav>
				<div class="flex flex-wrap items-center gap-3 border-t border-stone-200 pt-4 text-sm">
					{@render settings()}
				</div>
				<div class="flex flex-col items-start gap-3 border-t border-stone-200 pt-4 font-medium">
					{@render account()}
				</div>
			</div>
		{/if}
	</header>

	{#if data.user && !data.user.email_verified}
		<div
			class="flex flex-wrap items-center gap-x-3 bg-amber-50 px-4 py-2 text-sm text-amber-900 dark:bg-amber-950/40 dark:text-amber-200 print:hidden"
		>
			<span>{m.verify_banner()}</span>
			{#if resent}
				<span>{m.verify_resent()}</span>
			{:else}
				<button type="button" onclick={resend} class="underline">{m.verify_resend()}</button>
			{/if}
		</div>
	{/if}

	{@render children()}
</div>
