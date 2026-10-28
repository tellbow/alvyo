<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Me } from '#lib/api/client.js';
	import type { components } from '#lib/api/schema.js';
	import { m } from '#lib/paraglide/messages.js';
	import ProviderButtons from './ProviderButtons.svelte';

	type IdentityInfo = components['schemas']['IdentityInfo'];

	let { user }: { user: Me } = $props();

	let identities = $state<IdentityInfo[]>([]);
	let providers = $state<{ id: string; name: string }[]>([]);
	let error = $state('');

	const providerName = (id: string) => providers.find((p) => p.id === id)?.name ?? id;

	onMount(async () => {
		const [i, pr] = await Promise.all([api().GET('/me/identities'), api().GET('/auth/providers')]);
		identities = i.data?.identities ?? [];
		providers = pr.data?.providers ?? [];
	});

	async function unlink(provider: string) {
		error = '';
		const { data, response } = await api().DELETE('/me/identities/{provider}', {
			params: { path: { provider } }
		});
		if (data) identities = data.identities;
		else error = response.status === 409 ? m.signin_last() : m.error_generic();
	}
</script>

<div class="flex flex-col gap-3 text-sm" data-testid="signin-methods">
	<p class="text-stone-600">
		{user.has_password ? m.signin_password_set() : m.signin_password_none()}
	</p>

	{#if providers.length > 0}
		<div>
			<h3 class="font-medium">{m.provider_title()}</h3>
			{#if identities.length > 0}
				<ul class="mt-1 flex flex-col gap-1" data-testid="identities">
					{#each identities as i (i.provider)}
						<li class="flex items-center gap-3">
							<span class="flex-1"
								>{providerName(i.provider)}
								{#if i.email}<span class="text-stone-500">· {i.email}</span>{/if}</span
							>
							<button
								type="button"
								class="text-stone-500 underline"
								onclick={() => unlink(i.provider)}>{m.provider_unlink()}</button
							>
						</li>
					{/each}
				</ul>
			{/if}
			<div class="mt-2 flex flex-col gap-2">
				<ProviderButtons
					link
					exclude={identities.map((i) => i.provider)}
					label={(n) => m.provider_link({ provider: n })}
				/>
			</div>
		</div>
	{/if}

	{#if error}<p role="alert" class="text-red-700 dark:text-red-400">{error}</p>{/if}
</div>
