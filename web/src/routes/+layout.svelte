<script lang="ts">
	import './layout.css';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { choose } from '$lib/util/choose';
	import { Hydrated } from '$lib/util/hydrated.svelte';
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

	// The page's section in the navigation, whatever the language prefix.
	const here = $derived(deLocalizeUrl(page.url).pathname);
	function tab(section: string) {
		const on = here === section || here.startsWith(section + '/');
		return `rounded-full px-3.5 py-1.5 ${on ? 'bg-stone-900 text-stone-50 dark:bg-stone-200 dark:text-stone-900' : 'hover:text-accent-ink'}`;
	}

	async function resend() {
		const { response } = await api().POST('/auth/verify-email/resend');
		resent = response.ok;
	}
</script>

<div class="flex h-dvh flex-col bg-ground text-stone-900">
	<header class="flex items-center gap-6 border-b border-stone-200 px-5 py-2.5">
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
			class="flex items-center gap-1 rounded-full border border-stone-200 bg-surface p-1 text-sm font-medium"
		>
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
		</nav>
		<div class="ml-auto flex items-center gap-4 text-sm font-medium">
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
			{#if data.user}
				<a
					href={resolve('/account')}
					class="text-stone-600 hover:text-accent-ink"
					data-testid="current-user"
				>
					{data.user.username}
				</a>
				<button type="button" onclick={logout} class="hover:text-accent-ink"
					>{m.nav_logout()}</button
				>
			{:else}
				<a href={resolve('/login')} class="hover:text-accent-ink">{m.nav_login()}</a>
				<a
					href={resolve('/signup')}
					class="flex h-10 items-center rounded-full bg-accent px-5 font-semibold text-on-accent hover:bg-accent-hover"
				>
					{m.nav_signup()}
				</a>
			{/if}
		</div>
	</header>

	{#if data.user && !data.user.email_verified}
		<div
			class="flex items-center gap-3 bg-amber-50 px-4 py-2 text-sm text-amber-900 dark:bg-amber-950/40 dark:text-amber-200"
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
