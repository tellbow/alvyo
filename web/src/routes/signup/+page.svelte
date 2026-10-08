<script lang="ts">
	import { primaryButton } from '$lib/components/actions';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { goto, invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api, errorLocations } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import Field from '$lib/components/Field.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';
	import { getLocale } from '$lib/paraglide/runtime';
	import ProviderButtons from '$lib/account/ProviderButtons.svelte';

	const hydrated = new Hydrated();

	let email = $state('');
	let username = $state('');
	let displayName = $state('');
	let password = $state('');
	let website = $state(''); // spam trap, hidden from people
	let errors = $state<{ email?: string; username?: string; form?: string }>({});
	let busy = $state(false);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		errors = {};
		const { response, error } = await api().POST('/auth/signup', {
			body: { email, username, display_name: displayName, password, locale: getLocale(), website }
		});
		busy = false;
		if (response.ok) {
			await invalidateAll();
			await goto(resolve('/plan'));
			return;
		}
		const where = errorLocations(error);
		if (response.status === 409 && where.includes('body.email'))
			errors.email = m.signup_email_taken();
		else if (response.status === 409 && where.includes('body.username'))
			errors.username = m.signup_username_taken();
		else if (response.status === 429) errors.form = m.error_too_many();
		else errors.form = m.error_generic();
	}
</script>

<Seo title={m.signup_title()} index={false} />

<AuthCard title={m.signup_title()}>
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
			required
			pattern={'[a-z0-9_]{3,30}'}
			hint={m.hint_username()}
			error={errors.username}
			bind:value={username}
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
			bind:value={password}
		/>
		<input
			type="text"
			name="website"
			bind:value={website}
			tabindex="-1"
			autocomplete="off"
			class="hidden"
			aria-hidden="true"
		/>
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
	<p class="mt-6 text-sm">
		{m.signup_have_account()}
		<a href={resolve('/login')} class="text-accent-ink underline">{m.nav_login()}</a>
	</p>
</AuthCard>
