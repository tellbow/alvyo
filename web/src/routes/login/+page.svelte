<script lang="ts">
	import { primaryButton } from '$lib/components/actions';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, errorLocations } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import Field from '$lib/components/Field.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { safeRedirect } from '$lib/util/redirect';
	import { onMount } from 'svelte';
	import { browserSupportsWebAuthn, loginWithPasskey } from '$lib/account/passkeys';
	import ProviderButtons from '$lib/account/ProviderButtons.svelte';
	import OidcNotice from '$lib/account/OidcNotice.svelte';

	const hydrated = new Hydrated();
	let passkeys = $state(false);
	onMount(() => (passkeys = browserSupportsWebAuthn()));
	const redirect = $derived(safeRedirect(page.url.searchParams.get('redirect')));

	async function passkey() {
		error = '';
		busy = true;
		const problem = await loginWithPasskey();
		busy = false;
		if (!problem) {
			await invalidateAll();
			// eslint-disable-next-line svelte/no-navigation-without-resolve
			await goto(redirect);
		} else if (problem !== 'cancelled') {
			error = problem === 'rejected' ? m.passkey_login_rejected() : m.error_generic();
		}
	}

	let login = $state('');
	let password = $state('');
	let error = $state('');
	let busy = $state(false);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		const { response, error: err } = await api().POST('/auth/login', { body: { login, password } });
		busy = false;
		if (response.ok) {
			await invalidateAll();
			// safeRedirect only allows same-site paths, which resolve() cannot type.
			// eslint-disable-next-line svelte/no-navigation-without-resolve
			await goto(safeRedirect(page.url.searchParams.get('redirect')));
		} else if (response.status === 401) {
			error = m.login_invalid();
		} else if (response.status === 403 && errorLocations(err).includes('body.login')) {
			error = m.login_unverified(); // and a new link is on its way
		} else if (response.status === 429) {
			error = m.error_too_many();
		} else {
			error = m.error_generic();
		}
	}
</script>

<Seo title={m.login_title()} index={false} />

<AuthCard title={m.login_title()}>
	<OidcNotice />
	<form method="post" onsubmit={submit} class="flex flex-col gap-4">
		<Field
			label={m.field_login()}
			name="login"
			autocomplete="username"
			required
			bind:value={login}
		/>
		<Field
			label={m.field_password()}
			name="password"
			type="password"
			autocomplete="current-password"
			required
			bind:value={password}
		/>
		{#if error}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{error}</p>{/if}
		<button disabled={!hydrated.value || busy} class={primaryButton}>
			{m.login_submit()}
		</button>
	</form>
	<div class="mt-4 flex flex-col gap-2">
		{#if passkeys}
			<button
				type="button"
				disabled={!hydrated.value || busy}
				onclick={passkey}
				class="rounded-md px-4 py-2 ring-1 ring-stone-300 hover:bg-stone-50 disabled:opacity-60"
				>{m.passkey_login()}</button
			>
		{/if}
		<ProviderButtons {redirect} label={(name) => m.provider_login({ provider: name })} />
	</div>
	<div class="mt-6 flex flex-col gap-2 text-sm">
		<a href={resolve('/forgot-password')} class="text-accent-ink underline">{m.login_forgot()}</a>
		<p>
			{m.login_no_account()}
			<a href={resolve('/signup')} class="text-accent-ink underline">{m.nav_signup()}</a>
		</p>
	</div>
</AuthCard>
