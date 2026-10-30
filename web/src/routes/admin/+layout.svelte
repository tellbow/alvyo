<script lang="ts">
	import { goto, refreshAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { adminApi } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';

	// The admin portal (feedback issue 70): its own frame, German only, for
	// moderators and admins on the internal admin host.
	let { data, children } = $props();
	const hydrated = new Hydrated(); // for the end-to-end tests
	const staff = $derived(data.user && data.user.role !== 'user');
	const pages = [
		{ route: '/admin/(portal)/meldungen', path: '/admin/meldungen', label: 'Meldungen' },
		{ route: '/admin/(portal)/nutzer', path: '/admin/nutzer', label: 'Nutzer' },
		{ route: '/admin/(portal)/inhalte', path: '/admin/inhalte', label: 'Inhalte' },
		{ route: '/admin/(portal)/verlauf', path: '/admin/verlauf', label: 'Verlauf' }
	] as const;

	async function logout() {
		await adminApi().POST('/auth/logout');
		await refreshAll();
		await goto(resolve('/admin/login'));
	}
</script>

<div
	class="flex h-dvh flex-col bg-ground text-stone-900"
	data-testid="admin-frame"
	data-hydrated={hydrated.value || undefined}
>
	<header class="flex flex-wrap items-center gap-x-6 gap-y-2 border-b border-stone-200 px-4 py-2.5">
		<a href={resolve('/admin/(portal)')} class="font-display text-lg font-bold">Alvyo Admin</a>
		{#if staff}
			<nav class="flex gap-1 text-sm" aria-label="Admin">
				{#each pages as p (p.path)}
					<a
						href={resolve(p.route)}
						aria-current={page.url.pathname.startsWith(p.path) ? 'page' : undefined}
						class="rounded-full px-3 py-1.5 hover:bg-stone-100 aria-[current=page]:bg-stone-900 aria-[current=page]:text-white"
						>{p.label}</a
					>
				{/each}
			</nav>
			<span class="ml-auto text-sm text-stone-600">@{data.user?.username}</span>
			<button type="button" class="text-sm underline" onclick={logout}>{m.nav_logout()}</button>
		{/if}
	</header>
	<main id="content" class="flex-1 overflow-y-auto">{@render children()}</main>
</div>
