<script lang="ts">
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { api } from '$lib/api/client';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import Field from '$lib/components/Field.svelte';
	import { m } from '$lib/paraglide/messages';
	import Seo from '$lib/seo/Seo.svelte';

	const hydrated = new Hydrated();

	let password = $state('');
	let status = $state<'form' | 'done' | 'failed'>('form');

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		const token = page.url.searchParams.get('token') ?? '';
		const { response } = await api().POST('/auth/password/reset', { body: { token, password } });
		status = response.ok ? 'done' : 'failed';
	}
</script>

<Seo title={m.reset_title()} index={false} />

<AuthCard title={m.reset_title()}>
	{#if status === 'done'}
		<p role="status">
			{m.reset_done()}
			<a href={resolve('/login')} class="text-accent-ink underline">{m.nav_login()}</a>
		</p>
	{:else}
		<form method="post" onsubmit={submit} class="flex flex-col gap-4">
			<Field
				label={m.field_new_password()}
				name="password"
				type="password"
				autocomplete="new-password"
				required
				minlength={10}
				maxlength={128}
				hint={m.hint_password()}
				bind:value={password}
			/>
			{#if status === 'failed'}<p role="alert" class="text-sm text-red-700 dark:text-red-400">
					{m.reset_failed()}
				</p>{/if}
			<button
				disabled={!hydrated.value}
				class="rounded-md bg-accent px-4 py-2 text-on-accent hover:bg-accent-hover"
				>{m.reset_submit()}</button
			>
		</form>
	{/if}
</AuthCard>
