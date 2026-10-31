<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { refused, when, type AdminItem } from '#lib/admin/admin.js';
	import Search from '#lib/admin/Search.svelte';
	import UndoBar from '#lib/admin/UndoBar.svelte';
	import { adminApi } from '#lib/api/client.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	let done = $state<{ text: string; logId?: string }>();
	let error = $state('');

	const kinds: Record<AdminItem['kind'], string> = {
		route: 'Route',
		journey: 'Etappentour',
		collection: 'Sammlung'
	};
	const visibilities: Record<AdminItem['visibility'], string> = {
		private: 'privat',
		unlisted: 'mit Link',
		public: 'öffentlich'
	};
	const link = (it: AdminItem) =>
		it.kind === 'route'
			? resolve('/routes/[id]', { id: it.id })
			: it.kind === 'journey'
				? resolve('/journeys/[id]', { id: it.id })
				: resolve('/collections/[id]', { id: it.id });

	async function unpublish(it: AdminItem) {
		error = '';
		const { data: r, response } = await adminApi().POST('/admin/items/{kind}/{id}/unpublish', {
			params: { path: { kind: it.kind, id: it.id } }
		});
		if (!r) return void (error = refused(response.status));
		done = { text: `«${it.title}» ist jetzt privat.`, logId: r.log_id };
		await invalidateAll();
	}

	// Planned while the trail network was missing or older: matched again.
	let retrailing = $state('');
	async function retrail(it: AdminItem) {
		if (it.kind === 'collection') return;
		error = '';
		retrailing = it.id;
		const { response } = await adminApi().POST('/admin/items/{kind}/{id}/retrail', {
			params: { path: { kind: it.kind, id: it.id } }
		});
		retrailing = '';
		if (response.status === 409)
			return void (done = { text: `«${it.title}» passt schon zu den Wanderwegen.` });
		if (!response.ok) return void (error = refused(response.status));
		done = { text: `«${it.title}» an die Wanderwege angepasst.` };
	}
</script>

<Seo title="Inhalte" index={false} />

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<h1 class="mb-4 text-2xl font-semibold">Inhalte</h1>
	<Search label="Inhalte suchen" placeholder="Link, ID, Benutzername oder Wort im Titel" />
	<UndoBar bind:done />
	{#if error}<p role="alert" class="mb-4 text-sm text-red-700 dark:text-red-400">{error}</p>{/if}

	{#if data.q && data.items.length === 0}
		<p class="text-stone-600">Nichts gefunden.</p>
	{/if}
	<ul class="flex flex-col gap-3" data-testid="admin-items">
		{#each data.items as it (it.id)}
			<li
				class="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-stone-200 bg-surface p-4 text-sm"
				data-testid="admin-item"
			>
				<div class="min-w-0 flex-1">
					<p class="text-xs text-stone-500">
						{kinds[it.kind]} · {visibilities[it.visibility]} · geändert {when(it.updated_at)}
					</p>
					<a href={link(it)} class="font-semibold underline">{it.title}</a>
					<a
						href={`${resolve('/admin/(portal)/nutzer')}?q=${encodeURIComponent(it.owner)}`}
						class="ml-2 text-stone-600 underline">@{it.owner}</a
					>
				</div>
				{#if it.kind !== 'collection'}
					<button
						type="button"
						class="rounded px-2 py-1 ring-1 ring-stone-300 hover:bg-stone-50 disabled:opacity-50"
						disabled={retrailing === it.id}
						onclick={() => retrail(it)}
						>{retrailing === it.id ? 'Wird angepasst …' : 'An Wanderwege anpassen'}</button
					>
				{/if}
				{#if it.visibility !== 'private'}
					<button
						type="button"
						class="rounded bg-red-700 px-2 py-1 text-white"
						onclick={() => unpublish(it)}>Privat machen</button
					>
				{/if}
			</li>
		{/each}
	</ul>
</div>
