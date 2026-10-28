<script lang="ts">
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { onMount } from 'svelte';
	import { api } from '#lib/api/client.js';
	import type { components } from '#lib/api/schema.js';
	import { m } from '#lib/paraglide/messages.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';

	type Contact = components['schemas']['Contact'];

	const hydrated = new Hydrated();
	let contacts = $state<Contact[]>([]);
	let name = $state('');
	let email = $state('');
	let problem = $state('');

	onMount(async () => {
		const { data } = await api().GET('/me/contacts');
		contacts = data?.contacts ?? [];
	});

	async function add(e: SubmitEvent) {
		e.preventDefault();
		problem = '';
		const { data, response } = await api().POST('/me/contacts', {
			body: { name: name.trim(), email: email.trim() }
		});
		if (!data) {
			problem =
				response.status === 409
					? m.contacts_duplicate()
					: response.status === 422
						? m.contacts_full()
						: m.error_generic();
			return;
		}
		contacts = [...contacts, data].sort((a, b) => a.name.localeCompare(b.name));
		name = email = '';
	}

	async function remove(id: string) {
		const { response } = await api().DELETE('/me/contacts/{id}', { params: { path: { id } } });
		if (response.ok) contacts = contacts.filter((c) => c.id !== id);
	}
</script>

<ul class="flex flex-col gap-1 text-sm" data-testid="contacts">
	{#each contacts as c (c.id)}
		<li class="flex items-center gap-3">
			<span class="flex-1">{c.name} <span class="text-stone-500">{c.email}</span></span>
			<button type="button" class="text-stone-500 underline" onclick={() => remove(c.id)}
				>{m.contacts_remove()}</button
			>
		</li>
	{/each}
</ul>
{#if contacts.length < 10}
	<form
		method="post"
		onsubmit={add}
		class="mt-2 flex flex-wrap items-end gap-2 text-sm"
		data-testid="contact-form"
	>
		<label class="flex min-w-32 flex-1 flex-col gap-1">
			<span class="text-xs font-medium text-stone-600">{m.contacts_name()}</span>
			<input
				bind:value={name}
				required
				maxlength="80"
				autocomplete="off"
				class="rounded-md border border-stone-400 px-2 py-1"
			/>
		</label>
		<label class="flex min-w-32 flex-1 flex-col gap-1">
			<span class="text-xs font-medium text-stone-600">{m.contacts_email()}</span>
			<input
				bind:value={email}
				required
				type="email"
				maxlength="254"
				autocomplete="off"
				spellcheck="false"
				class="rounded-md border border-stone-400 px-2 py-1"
			/>
		</label>
		<button disabled={!hydrated.value} class={primaryButtonSmall}>{m.contacts_add()}</button>
	</form>
{/if}
{#if problem}<p role="alert" class="mt-1 text-sm text-red-700 dark:text-red-400">{problem}</p>{/if}
