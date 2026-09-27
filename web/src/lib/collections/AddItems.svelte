<script lang="ts">
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { candidates, type Candidate } from './candidates';

	/** [taken]: what the collection has, as "kind:id". */
	let { taken, onadd }: { taken: Set<string>; onadd: (c: Candidate) => Promise<unknown> } =
		$props();

	let all = $state<Candidate[]>();
	let query = $state('');
	let busy = $state(false);
	const shown = $derived(all ? candidates(all, taken, query) : []);

	// One's own routes and journeys and those shared, once the field is used.
	async function load() {
		if (all) return;
		const [routes, journeys, shared] = await Promise.all([
			api().GET('/routes'),
			api().GET('/journeys'),
			api().GET('/shared')
		]);
		all = [
			...(routes.data?.routes ?? []).map((r) => ({
				kind: 'route' as const,
				id: r.id,
				title: r.title
			})),
			...(journeys.data?.journeys ?? []).map((j) => ({
				kind: 'journey' as const,
				id: j.id,
				title: j.title
			})),
			...(shared.data?.routes ?? []).map((r) => ({
				kind: 'route' as const,
				id: r.id,
				title: r.title,
				owner: r.owner_username
			})),
			...(shared.data?.journeys ?? []).map((j) => ({
				kind: 'journey' as const,
				id: j.id,
				title: j.title,
				owner: j.owner_username
			}))
		];
	}

	async function add(c: Candidate) {
		busy = true;
		await onadd(c);
		busy = false;
	}
</script>

<div class="flex flex-col gap-1 text-sm" data-testid="collection-add">
	<input
		bind:value={query}
		onfocus={load}
		type="search"
		class="rounded-md border border-stone-300 px-2 py-1.5"
		placeholder={m.collection_add_search()}
		aria-label={m.collection_add_search()}
	/>
	{#if all && shown.length === 0}
		<p class="text-stone-600">{m.collection_add_none()}</p>
	{:else if shown.length > 0}
		<ul class="flex flex-col">
			{#each shown as c (`${c.kind}:${c.id}`)}
				<li>
					<button
						type="button"
						class="flex w-full items-baseline gap-2 rounded px-2 py-1 text-left hover:bg-stone-100 disabled:opacity-50"
						disabled={busy}
						data-testid="collection-add-item"
						onclick={() => add(c)}
					>
						<span class="min-w-0 flex-1 truncate">{c.title}</span>
						<span class="shrink-0 text-xs text-stone-600"
							>{c.kind === 'route'
								? m.collection_kind_route()
								: m.collection_kind_journey()}{c.owner
								? ` · ${m.collection_add_shared({ owner: c.owner })}`
								: ''}</span
						>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</div>
