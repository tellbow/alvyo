<script lang="ts">
	import { primaryButton } from '#lib/components/actions.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { api } from '#lib/api/client.js';
	import AuthCard from '#lib/components/AuthCard.svelte';
	import Field from '#lib/components/Field.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import Seo from '#lib/seo/Seo.svelte';

	const hydrated = new Hydrated();

	let email = $state('');
	let sent = $state(false);
	let error = $state('');

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		const { response } = await api().POST('/auth/password/forgot', { body: { email } });
		if (response.ok) sent = true;
		else error = response.status === 429 ? m.error_too_many() : m.error_generic();
	}
</script>

<Seo title={m.forgot_title()} index={false} />

<AuthCard title={m.forgot_title()}>
	{#if sent}
		<p role="status">{m.forgot_sent()}</p>
	{:else}
		<p class="mb-4 text-stone-600">{m.forgot_text()}</p>
		<form method="post" onsubmit={submit} class="flex flex-col gap-4">
			<Field
				label={m.field_email()}
				name="email"
				type="email"
				autocomplete="email"
				required
				bind:value={email}
			/>
			{#if error}<p role="alert" class="text-sm text-red-700 dark:text-red-400">{error}</p>{/if}
			<button disabled={!hydrated.value} class={primaryButton}>{m.forgot_submit()}</button>
		</form>
	{/if}
</AuthCard>
