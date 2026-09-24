<script lang="ts">
	import { resolve } from '$app/paths';
	import type { JourneyStage, StagePatch } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { getLocale } from '$lib/paraglide/runtime';
	import { SAC_COLOR } from '$lib/planner/colors';
	import { formatDistance, formatDuration, formatSAC } from '$lib/planner/route';
	import { stageColor } from './colors';
	import PlacePicker from './PlacePicker.svelte';
	import { placeDetail } from './places';
	import { sbbTimetableUrl } from './sbb';

	let {
		journeyId,
		stage: s,
		index: i,
		count,
		canEdit,
		pace,
		q,
		onpatch,
		onmove,
		onremove,
		onimport
	}: {
		journeyId: string;
		stage: JourneyStage;
		index: number;
		count: number;
		canEdit: boolean;
		pace: number;
		/** share token query string for links, or '' */
		q: string;
		onpatch: (body: StagePatch) => void;
		onmove: (delta: number) => void;
		onremove: () => void;
		/** Uploads a track file as the stage's route (replacing it if there is one). */
		onimport: (file: File) => Promise<unknown>;
	} = $props();

	let confirming = $state(false);
	let replacing = $state(false); // asked before a file replaces the route
	let importing = $state(false);
	let picking = $state<'start' | 'end'>();

	const ends = $derived(
		(['start', 'end'] as const).map((which) => ({
			which,
			label: which === 'start' ? m.place_start() : m.place_end(),
			place: which === 'start' ? s.start_place : s.end_place,
			near: which === 'start' ? s.route?.start : s.route?.end
		}))
	);
	const placesTitle = $derived(
		s.start_place && s.end_place ? `${s.start_place.name} – ${s.end_place.name}` : ''
	);

	function sbbUrl(which: 'start' | 'end'): string | undefined {
		const p = which === 'start' ? s.start_place : s.end_place;
		if (p?.kind !== 'pt_stop') return undefined;
		const date = s.planned_date;
		return which === 'start'
			? sbbTimetableUrl({ to: p.name, date, locale: getLocale() })
			: sbbTimetableUrl({ from: p.name, date, locale: getLocale() });
	}

	async function importFile(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		replacing = false;
		importing = true;
		await onimport(file);
		importing = false;
	}

	function pick(which: 'start' | 'end', id: string) {
		picking = undefined;
		onpatch(which === 'start' ? { start_place_id: id } : { end_place_id: id });
	}
</script>

{#snippet fileButton(label: string)}
	<label
		class="cursor-pointer rounded px-2 py-1 ring-1 ring-stone-300 hover:bg-stone-50"
		class:opacity-50={importing}
	>
		{label}
		<input
			type="file"
			accept=".gpx,.kml,.tcx,.fit"
			class="sr-only"
			disabled={importing}
			onchange={importFile}
		/>
	</label>
{/snippet}

<li
	class="rounded-md border border-stone-200 p-2 text-sm"
	data-testid="stage"
	data-status={s.status}
>
	<div class="flex items-center gap-2">
		<span class="inline-block size-3 rounded-full" style:background={stageColor(i)}></span>
		<span class="font-medium">{m.journey_stage({ n: i + 1 })}</span>
		{#if s.route}
			<span class="ml-auto text-xs text-stone-600 tabular-nums">
				{formatDistance(s.route.totals.distance_m)} · {formatDuration(
					s.route.totals.duration_s,
					pace
				)}
				· ↑ {Math.round(s.route.totals.ascent_m)} m
			</span>
			<span
				class="rounded px-1 text-xs font-semibold text-white"
				style:background={SAC_COLOR[`T${s.route.totals.sac_grade}`] ?? '#a8a29e'}
			>
				{formatSAC(s.route.totals.sac_grade, s.route.totals.sac_max)}
			</span>
		{:else}
			<span class="ml-auto text-xs text-stone-400">{m.journey_no_route()}</span>
		{/if}
	</div>

	{#if canEdit}
		<input
			class="mt-2 w-full rounded border border-stone-300 px-2 py-1"
			value={s.title}
			placeholder={placesTitle || m.journey_stage_title_placeholder()}
			aria-label={m.field_title()}
			onchange={(e) => onpatch({ title: e.currentTarget.value })}
		/>
		<div class="mt-2 flex gap-2">
			<input
				type="date"
				class="rounded border border-stone-300 px-1 py-0.5"
				value={s.planned_date ?? ''}
				aria-label={m.journey_date()}
				onchange={(e) => onpatch({ planned_date: e.currentTarget.value })}
			/>
			<select
				class="rounded border border-stone-300 px-1 py-0.5"
				value={s.status}
				aria-label={m.journey_status()}
				onchange={(e) => onpatch({ status: e.currentTarget.value as JourneyStage['status'] })}
			>
				<option value="planned">{m.status_planned()}</option>
				<option value="done">{m.status_done()}</option>
				<option value="skipped">{m.status_skipped()}</option>
			</select>
		</div>
	{:else}
		{#if s.title || placesTitle}<p class="mt-1">{s.title || placesTitle}</p>{/if}
		{#if s.planned_date}<p class="text-xs text-stone-500">{s.planned_date}</p>{/if}
	{/if}

	{#if s.route}
		<dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-2 gap-y-1 text-xs">
			{#each ends as e (e.which)}
				<dt class="text-stone-500">{e.label}</dt>
				<dd data-testid="stage-{e.which}">
					{#if e.place}
						<span class="font-medium">{e.place.name}</span>
						<span class="text-stone-500">
							· {placeDetail(e.place)}{#if e.place.suggested && canEdit}
								· {m.place_suggested()}{/if}
						</span>
					{:else}
						<span class="text-stone-400">{m.place_none()}</span>
					{/if}
					{#if canEdit}
						<button
							type="button"
							class="text-emerald-800 underline"
							onclick={() => (picking = picking === e.which ? undefined : e.which)}
						>
							{e.place ? m.place_change() : m.place_choose()}
						</button>
					{/if}
					{#if sbbUrl(e.which)}
						<!-- External timetable link: resolve() does not apply. -->
						<!-- eslint-disable svelte/no-navigation-without-resolve -->
						<a
							href={sbbUrl(e.which)}
							target="_blank"
							rel="noopener noreferrer"
							class="block text-emerald-800 underline"
							data-testid="sbb-{e.which}"
						>
							{e.which === 'start' ? m.sbb_to_start() : m.sbb_from_end()} ↗
						</a>
						<!-- eslint-enable svelte/no-navigation-without-resolve -->
					{/if}
				</dd>
			{/each}
		</dl>
		{#each ends as e (e.which)}
			{#if picking === e.which && e.near}
				<PlacePicker
					near={e.near}
					current={e.place}
					onpick={(id) => pick(e.which, id)}
					onclose={() => (picking = undefined)}
				/>
			{/if}
		{/each}
	{/if}

	{#if canEdit}
		<details class="mt-2 text-xs" open={!!(s.accommodation || s.notes)}>
			<summary class="cursor-pointer text-stone-600">{m.stage_details()}</summary>
			<div class="mt-2 flex flex-col gap-2">
				<div class="flex items-center gap-2">
					<input
						class="min-w-0 flex-1 rounded border border-stone-300 px-2 py-1"
						value={s.accommodation}
						placeholder={m.stage_accommodation_placeholder()}
						aria-label={m.stage_accommodation()}
						maxlength="200"
						onchange={(e) => onpatch({ accommodation: e.currentTarget.value })}
					/>
					<label class="flex items-center gap-1">
						<input
							type="checkbox"
							checked={s.accommodation_booked}
							onchange={(e) => onpatch({ accommodation_booked: e.currentTarget.checked })}
						/>
						{m.stage_booked()}
					</label>
				</div>
				<textarea
					class="rounded border border-stone-300 px-2 py-1"
					rows="3"
					value={s.notes}
					aria-label={m.stage_notes()}
					placeholder={m.stage_notes()}
					maxlength="5000"
					onchange={(e) => onpatch({ notes: e.currentTarget.value })}></textarea>
			</div>
		</details>

		{#if replacing}
			<div
				class="mt-2 flex flex-wrap items-center gap-2 text-xs"
				data-testid="stage-import-replace"
			>
				<span>{m.stage_import_replace()}</span>
				{@render fileButton(m.stage_import_choose())}
				<button type="button" class="underline" onclick={() => (replacing = false)}>
					{m.report_cancel()}
				</button>
			</div>
		{/if}

		<div class="mt-2 flex flex-wrap items-center gap-2 text-xs">
			<a
				href={resolve('/journeys/[id]/stages/[stage]', { id: journeyId, stage: s.id })}
				class="rounded bg-emerald-700 px-2 py-1 text-white hover:bg-emerald-800"
			>
				{s.route ? m.journey_edit_stage() : m.journey_plan_stage()}
			</a>
			{#if s.route && !replacing}
				<button
					type="button"
					class="rounded px-2 py-1 ring-1 ring-stone-300 hover:bg-stone-50"
					disabled={importing}
					onclick={() => (replacing = true)}
				>
					{importing ? m.import_running() : m.stage_import()}
				</button>
			{:else if !s.route}
				{@render fileButton(importing ? m.import_running() : m.stage_import())}
			{/if}
			<button
				type="button"
				class="px-1"
				disabled={i === 0}
				onclick={() => onmove(-1)}
				aria-label={m.journey_move_up()}>↑</button
			>
			<button
				type="button"
				class="px-1"
				disabled={i === count - 1}
				onclick={() => onmove(1)}
				aria-label={m.journey_move_down()}>↓</button
			>
			{#if confirming}
				<button
					type="button"
					class="ml-auto rounded bg-red-700 px-2 py-1 text-white"
					onclick={() => {
						confirming = false;
						onremove();
					}}
				>
					{m.journey_delete_stage_confirm()}
				</button>
			{:else}
				<button
					type="button"
					class="ml-auto text-stone-500 underline"
					onclick={() => (confirming = true)}
				>
					{m.journey_delete_stage()}
				</button>
			{/if}
		</div>
	{:else}
		{#if s.accommodation}
			<p class="mt-1 text-xs">
				{m.stage_accommodation()}: {s.accommodation}{#if s.accommodation_booked}
					({m.stage_booked()}){/if}
			</p>
		{/if}
		{#if s.notes}<p class="mt-1 text-xs whitespace-pre-line text-stone-600">{s.notes}</p>{/if}
		{#if s.route}
			<!-- The share token rides along; resolve() cannot express query strings. -->
			<!-- eslint-disable svelte/no-navigation-without-resolve -->
			<a
				href="{resolve('/routes/[id]', { id: s.route.id })}{q}"
				class="text-xs text-emerald-800 underline">→</a
			>
			<!-- eslint-enable svelte/no-navigation-without-resolve -->
		{/if}
	{/if}
</li>
