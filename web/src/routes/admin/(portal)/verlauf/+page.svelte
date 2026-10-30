<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { refused, when, type LogEntry } from '#lib/admin/admin.js';
	import { adminApi } from '#lib/api/client.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	let error = $state('');
	const filters = [
		['', 'Alle'],
		['meldungen', 'Meldungen'],
		['nutzer', 'Nutzer'],
		['inhalte', 'Inhalte']
	] as const;

	async function undo(e: LogEntry) {
		error = '';
		const { response } = await adminApi().POST('/admin/log/{id}/undo', {
			params: { path: { id: e.id } }
		});
		if (!response.ok) return void (error = refused(response.status));
		await invalidateAll();
	}
</script>

<Seo title="Verlauf" index={false} />

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<h1 class="mb-4 text-2xl font-semibold">Verlauf</h1>
	<nav class="mb-6 inline-flex rounded-lg bg-stone-100 p-0.5 text-sm" aria-label="Bereich">
		{#each filters as [area, label] (area)}
			<a
				href={`${resolve('/admin/(portal)/verlauf')}${area ? `?area=${area}` : ''}`}
				aria-current={(data.area ?? '') === area ? 'page' : undefined}
				class="rounded-md px-3 py-1 aria-[current=page]:bg-surface aria-[current=page]:font-semibold"
				>{label}</a
			>
		{/each}
	</nav>
	{#if error}<p role="alert" class="mb-4 text-sm text-red-700 dark:text-red-400">{error}</p>{/if}

	{#if data.entries.length === 0}
		<p class="text-stone-600">Noch nichts.</p>
	{/if}
	<ul
		class="flex flex-col divide-y divide-stone-200 rounded-xl border border-stone-200 bg-surface"
		data-testid="admin-log"
	>
		{#each data.entries as e (e.id)}
			<li
				class="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 text-sm"
				data-testid="admin-log-entry"
			>
				<div class="min-w-0 flex-1">
					<p class:line-through={e.undone_at} class:text-stone-500={e.undone_at}>{e.title}</p>
					<p class="text-xs text-stone-500">
						{when(e.at)} · {e.actor ? `@${e.actor}` : '–'}
						{#if e.undone_at}· rückgängig gemacht {when(e.undone_at)}{/if}
					</p>
				</div>
				{#if e.undoable}
					<button
						type="button"
						class="rounded px-2 py-1 ring-1 ring-stone-300"
						onclick={() => undo(e)}>Rückgängig</button
					>
				{/if}
			</li>
		{/each}
	</ul>
</div>
