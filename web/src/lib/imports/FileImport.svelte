<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api, type Proposal } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance, formatDuration } from '$lib/planner/route';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import ImportResult from './ImportResult.svelte';

	type Preview = components['schemas']['ImportPreviewOutputBody'];
	type Result = components['schemas']['ImportOutputBody'];
	type Mode = 'route' | 'routes' | 'journey' | 'stages';

	let { pace = 1 }: { pace?: number } = $props();

	const MAX_BYTES = 20 * 1024 * 1024;
	const hydrated = new Hydrated();

	let file = $state<File>();
	let preview = $state<Preview>();
	let mode = $state<Mode>();
	let title = $state('');
	let busy = $state(false);
	let problem = $state<string>();
	let result = $state<Result>();
	let stageCount = $state(2);
	let stages = $state<Proposal>();

	const importable = $derived(preview?.tracks.filter((t) => t.inside).length ?? 0);
	// Nights of a recording: as many stages as days split there.
	const nights = $derived(preview?.tracks.reduce((n, t) => n + t.nights, 0) ?? 0);

	function form(f: File, fields: Record<string, string | undefined> = {}) {
		const fd = new FormData();
		fd.append('file', f);
		for (const [k, v] of Object.entries(fields)) if (v) fd.append(k, v);
		return fd;
	}

	async function pick(e: Event) {
		file = (e.currentTarget as HTMLInputElement).files?.[0];
		preview = undefined;
		result = undefined;
		mode = undefined;
		problem = undefined;
		title = '';
		stages = undefined;
		if (!file) return;
		if (file.size > MAX_BYTES) {
			problem = m.import_too_big();
			return;
		}
		const f = file;
		busy = true;
		const { data } = await api().POST('/imports/preview', {
			body: { file: '' },
			bodySerializer: () => form(f)
		});
		busy = false;
		preview = data;
		if (!data) problem = m.import_unreadable();
		else if (data.tracks.length === 1) mode = 'route';
		stageCount = nights > 0 ? nights + 1 : 2;
	}

	/** Proposes the stages; nothing is created before the hiker agrees. */
	async function proposeStages(f: File) {
		const atNights = nights > 0 && stageCount === nights + 1;
		const { data, response } = await api().POST('/imports/stages', {
			body: { file: '' },
			bodySerializer: () => form(f, { days: atNights ? undefined : String(stageCount) })
		});
		busy = false;
		if (!data) {
			problem = response.status === 429 ? m.import_rate() : m.import_failed();
			return;
		}
		stages = data as Proposal;
		if (!title) title = data.title;
	}

	async function createJourney(e: SubmitEvent) {
		e.preventDefault();
		if (!stages) return;
		busy = true;
		const { data } = await api().POST('/journeys', {
			body: {
				title: title.trim() || preview?.tracks[0].name || 'Import',
				visibility: 'private',
				stages: stages.stages.map((st) => ({
					profile: st.profile as 'hike' | 'alpine',
					anchors: st.anchors,
					legs: st.legs,
					accommodation: st.accommodation,
					...(st.start_place ? { start_place_id: st.start_place.id } : {}),
					...(st.end_place ? { end_place_id: st.end_place.id } : {})
				}))
			}
		});
		busy = false;
		if (data) await goto(resolve('/journeys/[id]', { id: data.id }));
		else problem = m.import_failed();
	}

	async function run(e: SubmitEvent) {
		e.preventDefault();
		if (!file || !mode) return;
		const f = file;
		busy = true;
		problem = undefined;
		if (mode === 'stages') return proposeStages(f);
		const { data, response } = await api().POST('/imports', {
			body: { file: '', mode, title: title.trim() || undefined },
			bodySerializer: (b) => form(f, { mode: b?.mode, title: b?.title })
		});
		busy = false;
		if (!data) {
			problem = response.status === 429 ? m.import_rate() : m.import_failed();
			return;
		}
		if (data.skipped.length === 0 && data.journey_id) {
			await goto(resolve('/journeys/[id]', { id: data.journey_id }));
		} else if (data.skipped.length === 0 && data.routes.length === 1) {
			await goto(resolve('/routes/[id]', { id: data.routes[0].id }));
		} else {
			result = data;
			preview = undefined;
		}
	}
</script>

{#snippet stagesChoice()}
	<label class="flex items-center gap-2">
		<input type="radio" bind:group={mode} value="stages" onchange={() => (stages = undefined)} />
		{m.import_mode_stages()}
		<input
			type="number"
			min="2"
			max="60"
			class="w-16 rounded-md border border-stone-300 px-2 py-1"
			aria-label={m.import_mode_stages_unit()}
			bind:value={stageCount}
			onfocus={() => (mode = 'stages')}
			oninput={() => (stages = undefined)}
		/>
		{m.import_mode_stages_unit()}
	</label>
	{#if nights > 0}
		<p class="ml-6 text-xs text-stone-500">{m.import_stages_nights({ days: nights + 1 })}</p>
	{/if}
{/snippet}

<section class="rounded-md border border-stone-200 bg-surface p-4" data-testid="file-import">
	<h2 class="text-lg font-semibold">{m.import_file_title()}</h2>
	<p class="mt-1 text-sm text-stone-600">{m.import_file_intro()}</p>

	<input
		type="file"
		accept=".gpx,.kml,.tcx,.fit"
		onchange={pick}
		disabled={!hydrated.value || busy}
		aria-label={m.import_file_title()}
		class="mt-3 block text-sm file:mr-3 file:rounded-md file:border-0 file:bg-stone-100 file:px-3 file:py-1.5 hover:file:bg-stone-200"
	/>

	{#if preview}
		<ul class="mt-3 divide-y divide-stone-100 text-sm" data-testid="import-tracks">
			{#each preview.tracks as t, i (i)}
				<li class="flex gap-3 py-1.5">
					<span class="flex-1">{t.name}</span>
					<span class="text-stone-600 tabular-nums">{formatDistance(t.distance_m)}</span>
					{#if !t.inside}
						<span class="text-amber-800 dark:text-amber-200">{m.import_outside()}</span>
					{/if}
				</li>
			{/each}
		</ul>

		{#if importable === 0}
			<p class="mt-3 text-sm text-amber-800 dark:text-amber-200">{m.import_none_inside()}</p>
		{:else}
			<form method="post" onsubmit={run} class="mt-3 flex flex-col gap-3">
				{#if preview.tracks.length > 1}
					<fieldset class="flex flex-col gap-1 text-sm">
						<legend class="mb-1 font-medium">
							{m.import_mode_question({ n: preview.tracks.length })}
						</legend>
						<label class="flex items-center gap-2">
							<input type="radio" bind:group={mode} value="journey" />
							{m.import_mode_journey()}
						</label>
						<label class="flex items-center gap-2">
							<input type="radio" bind:group={mode} value="routes" />
							{m.import_mode_routes()}
						</label>
						<label class="flex items-center gap-2">
							<input type="radio" bind:group={mode} value="route" />
							{m.import_mode_route()}
						</label>
						{@render stagesChoice()}
					</fieldset>
				{:else}
					<fieldset class="flex flex-col gap-1 text-sm">
						<legend class="mb-1 font-medium">{m.import_mode_single_question()}</legend>
						<label class="flex items-center gap-2">
							<input type="radio" bind:group={mode} value="route" />
							{m.import_mode_single()}
						</label>
						{@render stagesChoice()}
					</fieldset>
				{/if}
				{#if mode && mode !== 'routes'}
					<input
						bind:value={title}
						maxlength="120"
						placeholder={preview.tracks[0].name}
						aria-label={m.field_title()}
						class="rounded-md border border-stone-300 px-3 py-2 text-sm"
					/>
				{/if}
				{#if !stages}
					<button
						disabled={!mode || busy}
						class="self-start rounded-md bg-accent px-4 py-2 text-sm text-on-accent hover:bg-accent-hover disabled:opacity-50"
					>
						{busy ? m.import_running() : mode === 'stages' ? m.jplan_submit() : m.import_submit()}
					</button>
				{/if}
			</form>
		{/if}
		{#if stages}
			<ol class="mt-3 flex flex-col gap-1 text-sm" data-testid="import-stages">
				{#each stages.stages as st, i (i)}
					<li class="flex flex-wrap gap-x-3 rounded-md border border-stone-200 px-3 py-2">
						<span class="font-medium">{m.jplan_day({ n: i + 1 })}</span>
						<span class="text-stone-600 tabular-nums"
							>{formatDistance(st.totals.distance_m)} · {formatDuration(st.totals.duration_s, pace)} ·
							↑ {Math.round(st.totals.ascent_m)} m</span
						>
						<span class="ml-auto" data-testid="import-stage-end"
							>→ {st.end_place ? st.end_place.name : m.jplan_to_end()}</span
						>
					</li>
				{/each}
			</ol>
			<form method="post" onsubmit={createJourney} class="mt-3">
				<button
					disabled={busy}
					class="rounded-md bg-accent px-4 py-2 text-sm text-on-accent hover:bg-accent-hover disabled:opacity-50"
				>
					{busy ? m.import_running() : m.jplan_create()}
				</button>
			</form>
		{/if}
	{:else if busy}
		<p class="mt-3 text-sm text-stone-500">…</p>
	{/if}

	{#if problem}
		<p class="mt-3 text-sm text-red-700 dark:text-red-400" role="alert">{problem}</p>
	{/if}
	{#if result}
		<ImportResult {result} />
	{/if}
</section>
