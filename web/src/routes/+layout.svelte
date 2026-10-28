<script lang="ts">
	import BugReport from '#lib/bugs/BugReport.svelte';
	import { analyticsActive, pageView } from '#lib/analytics.js';
	import ConsentBanner from '#lib/components/ConsentBanner.svelte';
	import './layout.css';
	import { afterNavigate, goto, refreshAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { setTheme, themes, type Theme } from '#lib/util/theme.js';
	import * as DropdownMenu from '#lib/components/ui/dropdown-menu/index.js';
	import Globe from '@lucide/svelte/icons/globe';
	import Moon from '@lucide/svelte/icons/moon';
	import Sun from '@lucide/svelte/icons/sun';
	import SunMoon from '@lucide/svelte/icons/sun-moon';
	import {
		deLocalizeUrl,
		getLocale,
		locales,
		setLocale,
		type Locale
	} from '#lib/paraglide/runtime.js';

	let { data, children } = $props();
	let resent = $state(false);

	async function logout() {
		await api().POST('/auth/logout');
		await refreshAll();
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
	const themeIcons = { system: SunMoon, light: Sun, dark: Moon };
	// The server's cookie value until one is chosen here.
	let theme = $derived(data.theme);
	function chooseTheme(t: Theme) {
		theme = t;
		setTheme(t);
	}
	const ThemeIcon = $derived(themeIcons[theme]);

	// The page's section in the navigation, whatever the language prefix.
	const here = $derived(deLocalizeUrl(page.url.href).pathname);
	const isHere = (section: string) => here === section || here.startsWith(section + '/');
	const current = (section: string) => (isHere(section) ? 'page' : undefined);
	function tab(section: string) {
		const on = isHere(section);
		return `rounded-full px-3.5 py-1.5 ${on ? 'bg-stone-900 text-stone-50 dark:bg-stone-200 dark:text-stone-900' : 'hover:text-accent-ink'}`;
	}

	// Past the navigation to the page's own content (its main part or panel).
	function skip(e: MouseEvent) {
		const target = document.querySelector<HTMLElement>('main, aside');
		if (!target) return;
		e.preventDefault();
		target.tabIndex = -1;
		target.focus();
	}

	// Below xl the links and settings go into a menu.
	let menu = $state(false);
	afterNavigate(({ to, shallow }) => {
		// Filters written into the address (shallow) are no page view.
		if (shallow) return;
		menu = false;
		// The page's route: to.route.id is null behind the language prefix.
		if (to && analyticsActive()) pageView(to.url, page.route.id);
	});

	async function resend() {
		const { response } = await api().POST('/auth/verify-email/resend');
		resent = response.ok;
	}

	// Back to the page after logging in, but not to the pages of logging in.
	const loginHref = $derived(
		/\/(login|signup|forgot-password|reset-password|verify-email)$/.test(page.url.pathname)
			? resolve('/login')
			: `${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname + page.url.search)}`
	);
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && (menu = false)} />

{#snippet links()}
	<a href={resolve('/discover')} class={tab('/discover')} aria-current={current('/discover')}
		>{m.nav_discover()}</a
	>
	<a href={resolve('/plan')} class={tab('/plan')} aria-current={current('/plan')}>{m.nav_plan()}</a>
	{#if data.user}
		<a href={resolve('/feed')} class={tab('/feed')} aria-current={current('/feed')}
			>{m.nav_feed()}</a
		>
		<a href={resolve('/routes')} class={tab('/routes')} aria-current={current('/routes')}
			>{m.nav_routes()}</a
		>
		<a href={resolve('/journeys')} class={tab('/journeys')} aria-current={current('/journeys')}
			>{m.nav_journeys()}</a
		>
		<a
			href={resolve('/collections')}
			class={tab('/collections')}
			aria-current={current('/collections')}>{m.nav_collections()}</a
		>
		{#if data.user.role !== 'user'}
			<a
				href={resolve('/moderation')}
				class={tab('/moderation')}
				aria-current={current('/moderation')}>{m.nav_moderation()}</a
			>
		{/if}
	{/if}
	<a href={resolve('/about')} class={tab('/about')} aria-current={current('/about')}
		>{m.nav_about()}</a
	>
{/snippet}

<!-- Round and outlined, as the bug report button beside them. -->
{#snippet settings()}
	<div class="flex items-center gap-2">
		<DropdownMenu.Root>
			<DropdownMenu.Trigger
				class="flex h-10 items-center gap-1.5 rounded-full border border-stone-300 bg-surface px-3 text-stone-900 uppercase hover:bg-stone-100 disabled:opacity-50"
				aria-label={m.nav_language()}
				title={m.nav_language()}
				disabled={!hydrated.value}
				data-testid="language"
			>
				<Globe class="size-4" aria-hidden="true" />{getLocale()}
			</DropdownMenu.Trigger>
			<DropdownMenu.Content align="end" class="w-auto min-w-36">
				<DropdownMenu.RadioGroup value={getLocale()} onValueChange={(v) => language(v as Locale)}>
					{#each locales as l (l)}
						<DropdownMenu.RadioItem value={l} lang={l} closeOnSelect
							>{languages[l]}</DropdownMenu.RadioItem
						>
					{/each}
				</DropdownMenu.RadioGroup>
			</DropdownMenu.Content>
		</DropdownMenu.Root>
		<DropdownMenu.Root>
			<DropdownMenu.Trigger
				class="flex size-10 items-center justify-center rounded-full border border-stone-300 bg-surface text-stone-900 hover:bg-stone-100 disabled:opacity-50"
				aria-label="{m.nav_theme()}: {themeNames[theme]()}"
				title="{m.nav_theme()}: {themeNames[theme]()}"
				disabled={!hydrated.value}
				data-testid="theme"
			>
				<ThemeIcon class="size-4" aria-hidden="true" />
			</DropdownMenu.Trigger>
			<DropdownMenu.Content align="end" class="w-auto min-w-36">
				<DropdownMenu.RadioGroup value={theme} onValueChange={(v) => chooseTheme(v as Theme)}>
					{#each themes as t (t)}
						{@const Icon = themeIcons[t]}
						<DropdownMenu.RadioItem value={t} closeOnSelect>
							<Icon aria-hidden="true" />{themeNames[t]()}
						</DropdownMenu.RadioItem>
					{/each}
				</DropdownMenu.RadioGroup>
			</DropdownMenu.Content>
		</DropdownMenu.Root>
	</div>
{/snippet}

<!-- In the phone menu: each choice in a row of its own, all visible. -->
{#snippet segmented<T extends string>(
	label: string,
	options: readonly T[],
	value: T,
	name: (o: T) => string,
	pick: (o: T) => void
)}
	<div
		role="radiogroup"
		aria-label={label}
		class="flex w-full rounded-full border border-stone-300 bg-surface p-1"
	>
		{#each options as o (o)}
			<button
				type="button"
				role="radio"
				aria-checked={o === value}
				disabled={!hydrated.value}
				class="flex-1 rounded-full px-2 py-1.5 text-center {o === value
					? 'bg-stone-900 text-stone-50 dark:bg-stone-200 dark:text-stone-900'
					: 'hover:bg-stone-100'}"
				onclick={() => pick(o)}>{name(o)}</button
			>
		{/each}
	</div>
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
			class="text-stone-900 hover:text-accent-ink"
			data-testid="current-user"
		>
			{data.user.username}
		</a>
		<button type="button" onclick={logout} class="text-left hover:text-accent-ink"
			>{m.nav_logout()}</button
		>
	{:else}
		<!-- resolve() gives the path; only the query is added -->
		<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
		<a href={loginHref} class="hover:text-accent-ink">{m.nav_login()}</a>
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
	<a
		href="#content"
		class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-md focus:bg-surface focus:px-3 focus:py-2"
		onclick={skip}>{m.skip_to_content()}</a
	>
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
				<div class="flex flex-col gap-2 border-t border-stone-200 pt-4 text-sm">
					{@render segmented(
						m.nav_language(),
						locales,
						getLocale(),
						(l) => languages[l],
						(l) => language(l)
					)}
					{@render segmented(m.nav_theme(), themes, theme, (t) => themeNames[t](), chooseTheme)}
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
	<ConsentBanner />
</div>
