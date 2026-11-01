<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { api, type Proposal } from '#lib/api/client.js';
	import { primaryButton } from '#lib/components/actions.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatDistance, formatDuration, formatHeight } from '#lib/planner/route.js';
	import { journeyBody, stageEnds } from './stages';

	// The days proposed, each end movable or removed (feedback issue 47), and
	// the journey made of them.
	let {
		proposal,
		title,
		pace,
		busy = $bindable(false),
		onends
	}: {
		proposal: Proposal;
		title: string;
		pace: number;
		busy?: boolean;
		/** Propose again with these ends. */
		onends: (ends: string[]) => void;
	} = $props();

	let failed = $state(false);

	function moveEnd(i: number, placeId: string) {
		onends(stageEnds(proposal).with(i, placeId));
	}

	async function create(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		failed = false;
		const { data } = await api().POST('/journeys', { body: journeyBody(title, proposal) });
		busy = false;
		if (data) await goto(resolve('/journeys/[id]', { id: data.id }));
		else failed = true;
	}

	/** Metres from the start to the end of stage i. */
	function along(i: number) {
		return proposal.stages.slice(0, i + 1).reduce((sum, st) => sum + st.totals.distance_m, 0);
	}
</script>

<p class="mt-3 text-xs text-stone-500" data-testid="stages-pick-hint">{m.stages_pick_hint()}</p>
<ol class="mt-1 flex flex-col gap-1 text-sm" data-testid="import-stages">
	{#each proposal.stages as st, i (i)}
		{@const last = i === proposal.stages.length - 1}
		<li class="flex flex-wrap gap-x-3 rounded-md border border-stone-200 px-3 py-2">
			<span class="font-medium">{m.jplan_day({ n: i + 1 })}</span>
			<span class="text-stone-600 tabular-nums"
				>{formatDistance(st.totals.distance_m)} · {formatDuration(st.totals.duration_s, pace)} · ↑&nbsp;{formatHeight(
					st.totals.ascent_m
				)}</span
			>
			<span class="ml-auto" data-testid="import-stage-end"
				>→ {st.end_place
					? st.end_place.name
					: last
						? m.jplan_to_end()
						: m.stages_end_at({ distance: formatDistance(along(i)) })}</span
			>
			{#if !last}
				<span class="flex w-full flex-wrap gap-2 text-xs">
					{#if st.earlier}
						<button
							type="button"
							class="underline"
							disabled={busy}
							data-testid="import-stage-earlier"
							onclick={() => moveEnd(i, st.earlier!.id)}
							>{m.jplan_earlier({ place: st.earlier.name })}</button
						>
					{/if}
					{#if st.later}
						<button
							type="button"
							class="underline"
							disabled={busy}
							data-testid="import-stage-later"
							onclick={() => moveEnd(i, st.later!.id)}
							>{m.jplan_later({ place: st.later.name })}</button
						>
					{/if}
					{#if proposal.stages.length > 2}
						<button
							type="button"
							class="underline"
							disabled={busy}
							data-testid="import-stage-merge"
							onclick={() => onends(stageEnds(proposal).toSpliced(i, 1))}>{m.stages_merge()}</button
						>
					{/if}
				</span>
			{/if}
		</li>
	{/each}
</ol>
<form method="post" onsubmit={create} class="mt-3">
	<button disabled={busy} class={primaryButton}>
		{busy ? m.import_running() : m.jplan_create()}
	</button>
</form>
{#if failed}
	<p class="mt-3 text-sm text-red-700 dark:text-red-400" role="alert">{m.import_failed()}</p>
{/if}
