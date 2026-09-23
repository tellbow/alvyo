<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.svg';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { getLocale, locales, setLocale, type Locale } from '$lib/paraglide/runtime';

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

	async function resend() {
		const { response } = await api().POST('/auth/verify-email/resend');
		resent = response.ok;
	}
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>

<div class="flex h-dvh flex-col bg-stone-50 text-stone-900">
	<header class="flex items-center gap-6 border-b border-stone-200 bg-white px-4 py-2">
		<a href={resolve('/')} class="text-lg font-semibold tracking-tight text-emerald-800">odysgeh</a>
		<nav class="flex flex-1 items-center gap-4 text-sm">
			<a href={resolve('/discover')} class="hover:text-emerald-700">{m.nav_discover()}</a>
			<a href={resolve('/plan')} class="hover:text-emerald-700">{m.nav_plan()}</a>
			{#if data.user}
				<a href={resolve('/feed')} class="hover:text-emerald-700">{m.nav_feed()}</a>
				<a href={resolve('/routes')} class="hover:text-emerald-700">{m.nav_routes()}</a>
				<a href={resolve('/journeys')} class="hover:text-emerald-700">{m.nav_journeys()}</a>
				<a href={resolve('/collections')} class="hover:text-emerald-700">{m.nav_collections()}</a>
				{#if data.user.role !== 'user'}
					<a href={resolve('/moderation')} class="hover:text-emerald-700">{m.nav_moderation()}</a>
				{/if}
			{/if}
			<a href={resolve('/about')} class="hover:text-emerald-700">{m.nav_about()}</a>
		</nav>
		<div class="flex items-center gap-3 text-sm">
			<select
				class="rounded border-0 bg-transparent py-0.5 text-stone-600"
				aria-label={m.nav_language()}
				value={getLocale()}
				disabled={!hydrated.value}
				onchange={(e) => language(e.currentTarget.value as Locale)}
				data-testid="language"
			>
				{#each locales as l (l)}
					<option value={l}>{languages[l]}</option>
				{/each}
			</select>
			{#if data.user}
				<a
					href={resolve('/account')}
					class="text-stone-600 hover:text-emerald-700"
					data-testid="current-user"
				>
					{data.user.username}
				</a>
				<button type="button" onclick={logout} class="hover:text-emerald-700"
					>{m.nav_logout()}</button
				>
			{:else}
				<a href={resolve('/login')} class="hover:text-emerald-700">{m.nav_login()}</a>
				<a
					href={resolve('/signup')}
					class="rounded-md bg-emerald-700 px-3 py-1.5 text-white hover:bg-emerald-800"
				>
					{m.nav_signup()}
				</a>
			{/if}
		</div>
	</header>

	{#if data.user && !data.user.email_verified}
		<div class="flex items-center gap-3 bg-amber-50 px-4 py-2 text-sm text-amber-900">
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
