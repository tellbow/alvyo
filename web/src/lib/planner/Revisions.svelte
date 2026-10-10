<script lang="ts">
	import { resolve } from '$app/paths';
	import { api, type Revision } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { savedAt } from '#lib/util/locale.js';
	import { formatDistance } from './route';

	// The earlier lines of a route, for its owner and editors; loaded when
	// opened.
	let { id }: { id: string } = $props();

	let revisions = $state<Revision[]>();

	async function load(e: Event) {
		if (!(e.currentTarget as HTMLDetailsElement).open || revisions) return;
		const { data } = await api().GET('/routes/{id}/revisions', { params: { path: { id } } });
		revisions = data?.revisions ?? [];
	}
</script>

<details class="text-sm" ontoggle={load} data-testid="revisions">
	<summary class="cursor-pointer font-medium">{m.revisions_title()}</summary>
	{#if revisions?.length === 0}
		<p class="mt-2 text-stone-600">{m.revisions_empty()}</p>
	{:else if revisions}
		<ul class="mt-2 flex flex-col gap-1">
			{#each revisions as r (r.version)}
				<li>
					<a
						href="{resolve('/routes/[id]', { id })}?version={r.version}"
						class="text-accent-ink underline">{savedAt(r.saved_at)}</a
					>
					<span class="text-stone-600">
						· {r.saved_by || m.revision_someone()} · {formatDistance(r.distance_m)}</span
					>
				</li>
			{/each}
		</ul>
	{/if}
</details>
