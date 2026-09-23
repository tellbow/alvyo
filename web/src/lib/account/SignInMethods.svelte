<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Me } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { intlLocale } from '$lib/util/locale';
	import { addPasskey, browserSupportsWebAuthn, type PasskeyProblem } from './passkeys';
	import ProviderButtons from './ProviderButtons.svelte';

	type Passkey = components['schemas']['PasskeyInfo'];
	type IdentityInfo = components['schemas']['IdentityInfo'];

	let { user }: { user: Me } = $props();

	let passkeys = $state<Passkey[]>([]);
	let identities = $state<IdentityInfo[]>([]);
	let providers = $state<{ id: string; name: string }[]>([]);
	let supported = $state(false);
	let adding = $state(false);
	let name = $state('');
	let password = $state('');
	let error = $state('');
	let busy = $state(false);

	const day = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			dateStyle: 'medium'
		})
	);
	const providerName = (id: string) => providers.find((p) => p.id === id)?.name ?? id;

	const problems: Record<PasskeyProblem, () => string> = {
		cancelled: () => '',
		password: m.account_delete_wrong,
		again: m.passkey_again,
		rejected: m.passkey_rejected,
		other: m.error_generic
	};

	onMount(async () => {
		supported = browserSupportsWebAuthn();
		const [p, i, pr] = await Promise.all([
			api().GET('/me/passkeys'),
			api().GET('/me/identities'),
			api().GET('/auth/providers')
		]);
		passkeys = p.data?.passkeys ?? [];
		identities = i.data?.identities ?? [];
		providers = pr.data?.providers ?? [];
	});

	async function add(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = '';
		const problem = await addPasskey(name.trim(), password);
		busy = false;
		if (problem) {
			error = problems[problem]();
			return;
		}
		adding = false;
		name = password = '';
		passkeys = (await api().GET('/me/passkeys')).data?.passkeys ?? passkeys;
	}

	async function removePasskey(id: string) {
		error = '';
		const { data, response } = await api().DELETE('/me/passkeys/{id}', {
			params: { path: { id } }
		});
		if (data) passkeys = data.passkeys;
		else error = response.status === 409 ? m.signin_last() : m.error_generic();
	}

	async function unlink(provider: string) {
		error = '';
		const { data, response } = await api().DELETE('/me/identities/{provider}', {
			params: { path: { provider } }
		});
		if (data) identities = data.identities;
		else error = response.status === 409 ? m.signin_last() : m.error_generic();
	}
</script>

<h2 class="mt-8 text-lg font-semibold">{m.signin_title()}</h2>
<div class="mt-2 flex flex-col gap-3 text-sm" data-testid="signin-methods">
	<p class="text-stone-600">
		{user.has_password ? m.signin_password_set() : m.signin_password_none()}
	</p>

	<div>
		<h3 class="font-medium">{m.passkey_title()}</h3>
		{#if passkeys.length === 0}
			<p class="text-stone-600">{m.passkey_none()}</p>
		{:else}
			<ul class="mt-1 flex flex-col gap-1" data-testid="passkeys">
				{#each passkeys as p (p.id)}
					<li class="flex items-center gap-3">
						<span class="flex-1"
							>{p.name}
							<span class="text-stone-500"
								>· {m.passkey_added({ date: day.format(new Date(p.created_at)) })}</span
							></span
						>
						<button
							type="button"
							class="text-stone-500 underline"
							onclick={() => removePasskey(p.id)}>{m.passkey_remove()}</button
						>
					</li>
				{/each}
			</ul>
		{/if}
		{#if supported}
			{#if adding}
				<form method="post" onsubmit={add} class="mt-2 flex flex-col gap-2">
					<input
						bind:value={name}
						required
						maxlength="60"
						placeholder={m.passkey_name()}
						aria-label={m.passkey_name()}
						class="rounded-md border border-stone-300 px-3 py-1.5"
					/>
					{#if user.has_password}
						<input
							type="password"
							bind:value={password}
							required
							autocomplete="current-password"
							placeholder={m.field_password()}
							aria-label={m.field_password()}
							class="rounded-md border border-stone-300 px-3 py-1.5"
						/>
					{/if}
					<button
						disabled={busy}
						class="self-start rounded-md bg-emerald-700 px-3 py-1.5 text-white hover:bg-emerald-800 disabled:opacity-60"
						>{m.passkey_create()}</button
					>
				</form>
			{:else}
				<button
					type="button"
					class="mt-2 rounded-md px-3 py-1.5 ring-1 ring-stone-300 hover:bg-stone-50"
					onclick={() => (adding = true)}>{m.passkey_add()}</button
				>
			{/if}
		{/if}
	</div>

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

	{#if error}<p role="alert" class="text-red-700">{error}</p>{/if}
</div>
