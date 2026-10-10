<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me } from '#lib/api/client.js';
	import { mainAction } from '#lib/components/actions.js';
	import { m } from '#lib/paraglide/messages.js';

	// «Als eigene Route bearbeiten»: a private copy, opened where it is
	// changed. Without a login, the login first and back here.
	let {
		kind,
		id,
		token,
		user
	}: { kind: 'routes' | 'journeys'; id: string; token?: string; user: Me | null } = $props();

	let busy = $state(false);
	let failed = $state(false);
	const label = $derived(kind === 'routes' ? m.route_copy() : m.journey_copy());
	const loginHref = $derived(
		`${resolve('/login')}?redirect=${encodeURIComponent(page.url.pathname + page.url.search)}`
	);

	async function copy() {
		busy = true;
		failed = false;
		const opts = { params: { path: { id }, query: token ? { t: token } : {} } };
		const { data } =
			kind === 'routes'
				? await api().POST('/routes/{id}/copy', opts)
				: await api().POST('/journeys/{id}/copy', opts);
		busy = false;
		if (!data) {
			failed = true;
			return;
		}
		await goto(
			kind === 'routes'
				? resolve('/plan/[id]', { id: data.id })
				: resolve('/journeys/[id]', { id: data.id })
		);
	}
</script>

{#if user}
	<button type="button" class={mainAction} onclick={copy} disabled={busy} data-testid="copy">
		✎ {label}
	</button>
{:else}
	<!-- resolve() gives the path; only the query is added -->
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
	<a href={loginHref} class={mainAction} data-testid="copy">✎ {label}</a>
{/if}
{#if failed}
	<p role="alert" class="w-full text-sm text-red-700 dark:text-red-400">{m.copy_failed()}</p>
{/if}
