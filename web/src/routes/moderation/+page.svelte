<script lang="ts">
	import { resolve } from '$app/paths';
	import { api } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { intlLocale } from '$lib/util/locale';

	type Report = components['schemas']['Report'];

	let { data } = $props();
	// svelte-ignore state_referenced_locally
	let reports = $state(data.reports);
	let error = $state('');
	const when = $derived(
		new Intl.DateTimeFormat(intlLocale(), {
			dateStyle: 'medium',
			timeStyle: 'short',
			timeZone: 'Europe/Zurich'
		})
	);

	const kinds: Record<Report['kind'], () => string> = {
		route: m.collection_kind_route,
		journey: m.collection_kind_journey,
		comment: m.moderation_kind_comment,
		user: m.moderation_kind_user,
		photo: m.moderation_kind_photo
	};
	const removeLabel: Record<Report['kind'], () => string> = {
		route: m.moderation_unpublish,
		journey: m.moderation_unpublish,
		comment: m.moderation_delete_comment,
		user: m.moderation_ban,
		photo: m.moderation_delete_photo
	};
	const reasons: Record<Report['reason'], () => string> = {
		spam: m.report_reason_spam,
		offensive: m.report_reason_offensive,
		dangerous: m.report_reason_dangerous,
		other: m.report_reason_other
	};

	async function resolveReport(r: Report, resolution: 'dismissed' | 'removed') {
		error = '';
		const { response } = await api().POST('/moderation/reports/{id}/resolve', {
			params: { path: { id: r.id } },
			body: { resolution }
		});
		if (response.ok) reports = reports.filter((x) => x.target_id !== r.target_id);
		else error = m.error_generic();
	}
</script>

<svelte:head><title>{m.moderation_title()} · odysgeh</title></svelte:head>

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<h1 class="text-2xl font-semibold">{m.moderation_title()}</h1>
	<p class="mt-1 text-stone-600">{m.moderation_intro()}</p>
	{#if error}<p role="alert" class="mt-3 text-sm text-red-700">{error}</p>{/if}

	{#if reports.length === 0}
		<p class="mt-6 text-stone-600">{m.moderation_empty()}</p>
	{:else}
		<ul class="mt-6 flex flex-col gap-3" data-testid="reports">
			{#each reports as r (r.id)}
				<li class="rounded-md border border-stone-200 bg-white p-3 text-sm" data-testid="report">
					<p class="text-xs text-stone-500">
						{kinds[r.kind]()} · {reasons[r.reason]()} · {when.format(new Date(r.created_at))}
						· {m.moderation_by({ user: r.reporter || '–' })}
						{#if r.reports > 1}· {m.moderation_count({ n: r.reports })}{/if}
					</p>
					{#if r.kind === 'photo' && !r.gone}
						<img
							src="/api/v1/photos/{r.target_id}/thumb"
							alt={r.excerpt}
							class="mt-1 max-h-40 rounded"
						/>
					{/if}
					<p class="mt-1 whitespace-pre-line">{r.excerpt}</p>
					{#if r.note}<p class="mt-1 text-stone-600 italic">«{r.note}»</p>{/if}
					<p class="mt-1 text-xs text-stone-500">
						{#if r.gone}
							{m.moderation_gone()}
						{:else if r.item_kind && r.item_id}
							<a
								href={r.item_kind === 'route'
									? resolve('/routes/[id]', { id: r.item_id })
									: resolve('/journeys/[id]', { id: r.item_id })}
								class="underline">{m.moderation_open()}</a
							>
						{/if}
						{#if r.subject}
							· @{r.subject}
						{/if}
					</p>
					<div class="mt-2 flex gap-2">
						<button
							type="button"
							class="rounded px-2 py-1 ring-1 ring-stone-300"
							onclick={() => resolveReport(r, 'dismissed')}>{m.moderation_dismiss()}</button
						>
						{#if !r.gone}
							<button
								type="button"
								class="rounded bg-red-700 px-2 py-1 text-white"
								onclick={() => resolveReport(r, 'removed')}>{removeLabel[r.kind]()}</button
							>
						{/if}
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</main>
