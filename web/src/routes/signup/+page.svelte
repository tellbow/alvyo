<script lang="ts">
	import { primaryButton } from '#lib/components/actions.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { resolve } from '$app/paths';
	import { api, errorLocations } from '#lib/api/client.js';
	import AuthCard from '#lib/components/AuthCard.svelte';
	import Field from '#lib/components/Field.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';
	import { getLocale } from '#lib/paraglide/runtime.js';
	import ProviderButtons from '#lib/account/ProviderButtons.svelte';
	import { formProof } from '#lib/spam/proof.js';
	import Trap from '#lib/spam/Trap.svelte';
	import { onMount } from 'svelte';
	import { badChars } from '#lib/account/username.js';

	const hydrated = new Hydrated();

	let email = $state('');
	let username = $state('');
	let displayName = $state('');
	let password = $state('');
	let errors = $state<{ email?: string; username?: string; password?: string; form?: string }>({});
	// Wrong characters show while typing; the length once the field is left.
	let usernameLeft = $state(false);
	const usernameError = $derived.by(() => {
		const bad = badChars(username);
		if (bad.length > 0)
			return m.signup_username_chars({
				chars: bad.map((c) => (c === ' ' ? m.signup_username_space() : c)).join(' ')
			});
		if (!usernameLeft || !username) return undefined;
		if (username.length < 3) return m.signup_username_short();
		if (username.length > 30) return m.signup_username_long();
		return undefined;
	});
	let busy = $state(false);
	let sent = $state<string>();
	const proof = formProof();
	onMount(() => void proof.start());

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		errors = {};
		const { response, error } = await api().POST('/auth/signup', {
			body: {
				email,
				username,
				display_name: displayName,
				password,
				locale: getLocale(),
				...(await proof.take(e))
			}
		});
		busy = false;
		// The same answer for a new address and one with an account: the
		// e-mail says which (the page does not tell others who signed up).
		if (response.ok) {
			sent = email;
			return;
		}
		const where = errorLocations(error);
		if (response.status === 409 && where.includes('body.username'))
			errors.username = m.signup_username_taken();
		else if (where.includes('body.email')) errors.email = m.signup_email_rejected();
		else if (where.includes('body.username')) errors.username = m.hint_username();
		else if (where.includes('body.password')) errors.password = m.hint_password();
		else if (response.status === 429) errors.form = m.error_too_many();
		else errors.form = m.error_generic();
	}
</script>

<Seo title={m.signup_title()} index={false} />

<AuthCard title={m.signup_title()}>
	{#if sent}
		<p role="status" data-testid="signup-sent">{m.signup_sent({ email: sent })}</p>
	{:else}
		<form method="post" onsubmit={submit} class="flex flex-col gap-4">
			<Field
				label={m.field_email()}
				name="email"
				type="email"
				autocomplete="email"
				required
				error={errors.email}
				bind:value={email}
			/>
			<Field
				label={m.field_username()}
				name="username"
				autocomplete="username"
				autocapitalize="none"
				required
				pattern={'[a-z0-9_]{3,30}'}
				hint={m.hint_username()}
				error={errors.username ?? usernameError}
				onblur={() => (usernameLeft = true)}
				oninvalid={() => (usernameLeft = true)}
				bind:value={
					() => username,
					(v) => {
						username = v.toLowerCase();
						errors.username = undefined; // «taken» was for the name before
					}
				}
			/>
			<Field
				label={m.field_display_name()}
				name="display_name"
				autocomplete="name"
				required
				maxlength={60}
				bind:value={displayName}
			/>
			<Field
				label={m.field_password()}
				name="password"
				type="password"
				autocomplete="new-password"
				required
				minlength={10}
				maxlength={128}
				hint={m.hint_password()}
				error={errors.password}
				bind:value={password}
			/>
			<Trap />
			{#if errors.form}<p role="alert" class="text-sm text-red-700 dark:text-red-400">
					{errors.form}
				</p>{/if}
			<button disabled={!hydrated.value || busy} class={primaryButton}>
				{m.signup_submit()}
			</button>
		</form>
		<div class="mt-4 flex flex-col gap-2">
			<ProviderButtons redirect="/plan" label={(name) => m.provider_signup({ provider: name })} />
		</div>
	{/if}
	<p class="mt-6 text-sm">
		{m.signup_have_account()}
		<a href={resolve('/login')} class="text-accent-ink underline">{m.nav_login()}</a>
	</p>
</AuthCard>
