<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type CollectionSummary } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';

	let { kind, id }: { kind: 'route' | 'journey'; id: string } = $props();

	let mine = $state<CollectionSummary[]>();
	let message = $state('');

	onMount(async () => {
		const { data } = await api().GET('/collections');
		mine = data?.collections ?? [];
	});

	async function add(c: CollectionSummary) {
		const { response } = await api().POST('/collections/{id}/items', {
			params: { path: { id: c.id } },
			body: kind === 'route' ? { route_id: id } : { journey_id: id }
		});
		message = response.ok
			? m.collection_added({ title: c.title })
			: response.status === 409
				? m.collection_already({ title: c.title })
				: m.error_generic();
	}
</script>

<div class="flex flex-col gap-1 text-sm">
	<select
		class="rounded-md border border-stone-300 px-2 py-1.5"
		aria-label={m.collection_add_to()}
		data-testid="add-to-collection"
		disabled={!mine}
		onchange={(e) => {
			const c = mine?.find((x) => x.id === e.currentTarget.value);
			e.currentTarget.value = '';
			if (c) add(c);
		}}
	>
		<option value="">{m.collection_add_to()}</option>
		{#each mine ?? [] as c (c.id)}
			<option value={c.id}>{c.title}</option>
		{/each}
	</select>
	{#if message}<p class="text-xs text-stone-600" role="status">{message}</p>{/if}
</div>
