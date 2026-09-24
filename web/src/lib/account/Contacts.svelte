<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';

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

<h2 class="mt-8 text-lg font-semibold">{m.contacts_title()}</h2>
<p class="mt-1 text-sm text-stone-600">{m.contacts_intro()}</p>
<ul class="mt-2 flex flex-col gap-1 text-sm" data-testid="contacts">
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
	<form method="post" onsubmit={add} class="mt-2 flex flex-wrap gap-2 text-sm">
		<input
			bind:value={name}
			required
			maxlength="80"
			placeholder={m.contacts_name()}
			aria-label={m.contacts_name()}
			class="min-w-0 flex-1 rounded-md border border-stone-300 px-2 py-1"
		/>
		<input
			bind:value={email}
			required
			type="email"
			maxlength="254"
			placeholder={m.contacts_email()}
			aria-label={m.contacts_email()}
			class="min-w-0 flex-1 rounded-md border border-stone-300 px-2 py-1"
		/>
		<button
			disabled={!hydrated.value}
			class="rounded-md bg-emerald-700 px-3 py-1 text-white hover:bg-emerald-800 disabled:opacity-50"
			>{m.contacts_add()}</button
		>
	</form>
{/if}
{#if problem}<p role="alert" class="mt-1 text-sm text-red-700">{problem}</p>{/if}
