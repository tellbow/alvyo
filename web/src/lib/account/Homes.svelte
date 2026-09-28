<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type FoundPlace, type Home } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import PlaceSearch from '$lib/planner/PlaceSearch.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	const hydrated = new Hydrated();
	let homes = $state<Home[]>([]);
	let name = $state('');
	let found = $state<FoundPlace>();
	let problem = $state('');

	onMount(async () => {
		const { data } = await api().GET('/me/homes');
		homes = data?.homes ?? [];
	});

	async function add(e: SubmitEvent) {
		e.preventDefault();
		if (!found) return;
		problem = '';
		const { data, response } = await api().POST('/me/homes', {
			body: { name: name.trim(), address: found.name, lon: found.at[0], lat: found.at[1] }
		});
		if (!data) {
			problem = response.status === 422 ? m.homes_full() : m.error_generic();
			return;
		}
		homes = [...homes, data];
		name = '';
		found = undefined;
	}

	async function remove(id: string) {
		const { response } = await api().DELETE('/me/homes/{id}', { params: { path: { id } } });
		if (response.ok) homes = homes.filter((h) => h.id !== id);
	}
</script>

<h2 class="mt-8 text-lg font-semibold">{m.homes_title()}</h2>
<p class="mt-1 text-sm text-stone-600">{m.homes_intro()}</p>
<ul class="mt-2 flex flex-col gap-1 text-sm" data-testid="homes">
	{#each homes as h (h.id)}
		<li class="flex items-center gap-3">
			<span class="flex-1">{h.name} <span class="text-stone-500">{h.address}</span></span>
			<button type="button" class="text-stone-500 underline" onclick={() => remove(h.id)}
				>{m.homes_remove()}</button
			>
		</li>
	{/each}
</ul>
{#if homes.length < 5}
	<form method="post" onsubmit={add} class="mt-2 flex flex-col gap-2 text-sm">
		<input
			bind:value={name}
			required
			maxlength="60"
			placeholder={m.homes_name_placeholder()}
			aria-label={m.homes_name()}
			class="rounded-md border border-stone-300 px-2 py-1"
			data-testid="home-name"
		/>
		{#if found}
			<p class="flex items-center gap-2">
				<span class="flex-1" data-testid="home-address">{found.name}</span>
				<button type="button" class="text-stone-500 underline" onclick={() => (found = undefined)}
					>{m.homes_remove()}</button
				>
			</p>
		{:else}
			<PlaceSearch
				label={m.homes_address()}
				near={() => undefined}
				onpick={(p) => (found = p)}
				inputClass="w-full rounded-md border border-stone-300 px-2 py-1"
			/>
		{/if}
		<button
			disabled={!hydrated.value || !found || !name.trim()}
			class="self-start rounded-md bg-accent px-3 py-1 text-on-accent hover:bg-accent-hover disabled:opacity-50"
			data-testid="home-add">{m.homes_add()}</button
		>
	</form>
{/if}
{#if problem}<p role="alert" class="mt-1 text-sm text-red-700 dark:text-red-400">{problem}</p>{/if}
