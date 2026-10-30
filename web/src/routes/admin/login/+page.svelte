<script lang="ts">
	import { goto, refreshAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { adminApi } from '#lib/api/client.js';
	import { primaryButton } from '#lib/components/actions.js';
	import Field from '#lib/components/Field.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	let login = $state('');
	let password = $state('');
	let error = $state('');
	let busy = $state(false);

	// A session of the admin host: its cookie is not the public site's.
	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		const { response } = await adminApi().POST('/auth/login', { body: { login, password } });
		busy = false;
		if (response.ok) {
			await refreshAll();
			await goto(resolve('/admin/(portal)'));
		} else if (response.status === 401) {
			error = m.login_invalid();
		} else if (response.status === 429) {
			error = m.error_too_many();
		} else {
			error = m.error_generic();
		}
	}
</script>

<Seo title="Admin" index={false} />

<div class="mx-auto mt-16 w-full max-w-sm px-4">
	<h1 class="text-2xl font-semibold">Anmelden</h1>
	{#if data.user}
		<p class="mt-2 text-sm text-stone-600" data-testid="admin-no-role">
			@{data.user.username} ist nicht Moderator:in. Melde dich mit einem anderen Konto an.
		</p>
	{/if}
	<form method="post" onsubmit={submit} class="mt-6 flex flex-col gap-4">
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
		<button type="submit" class={primaryButton} disabled={busy}>{m.login_submit()}</button>
	</form>
</div>
