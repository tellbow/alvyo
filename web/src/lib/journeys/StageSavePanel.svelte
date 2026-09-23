<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api, type Journey, type Route } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import type { Planner } from '$lib/planner/planner.svelte';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	let {
		planner,
		journey,
		index,
		route
	}: { planner: Planner; journey: Journey; index: number; route?: Route } = $props();
	const hydrated = new Hydrated();
	let status = $state<'idle' | 'saving' | 'conflict' | 'failed'>('idle');

	const stage = $derived(journey.stage_list[index]);
	const canSave = $derived(planner.complete && (!route || planner.dirty) && status !== 'saving');
	const back = $derived(resolve('/journeys/[id]', { id: journey.id }));

	async function save(e: SubmitEvent) {
		e.preventDefault();
		status = 'saving';
		const content = planner.content();
		const { response } = route
			? await api().PATCH('/routes/{id}', {
					params: { path: { id: route.id }, header: { 'If-Match': `"${route.version}"` } },
					body: content
				})
			: await api().POST('/journeys/{id}/stages/{stage}/route', {
					params: { path: { id: journey.id, stage: stage.id } },
					body: content
				});
		if (!response.ok) {
			status = response.status === 412 ? 'conflict' : 'failed';
			return;
		}
		planner.markSaved();
		await goto(back);
	}
</script>

<form
	method="post"
	onsubmit={save}
	class="flex flex-col gap-2 rounded-md border border-stone-200 p-3"
	data-testid="save-panel"
>
	<p class="text-sm">
		<span class="font-medium">{m.journey_stage({ n: index + 1 })}</span>
		{#if stage.title}· {stage.title}{/if}
		<br /><span class="text-xs text-stone-500">{journey.title}</span>
	</p>
	<button
		disabled={!hydrated.value || !canSave}
		class="rounded-md bg-emerald-700 px-3 py-1.5 text-sm text-white hover:bg-emerald-800 disabled:opacity-50"
	>
		{status === 'saving' ? m.saving() : m.stage_save()}
	</button>
	{#if status === 'conflict'}
		<p class="text-xs text-red-700" role="alert">{m.save_conflict()}</p>
	{:else if status === 'failed'}
		<p class="text-xs text-red-700" role="alert">{m.save_failed()}</p>
	{:else if !planner.complete && planner.anchors.length > 1}
		<p class="text-xs text-stone-500">{m.save_incomplete()}</p>
	{/if}
	<a href={back} class="text-xs text-emerald-800 underline">{m.journey_back()}</a>
</form>
