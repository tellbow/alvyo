<script lang="ts">
	import { resolve } from '$app/paths';
	import { api, type Proposal } from '#lib/api/client.js';
	import { primaryButton } from '#lib/components/actions.js';
	import ImportPreview from '#lib/imports/ImportPreview.svelte';
	import StageList from '#lib/imports/StageList.svelte';
	import { endsWithSpot, stageView } from '#lib/imports/stages.js';
	import { m } from '#lib/paraglide/messages.js';
	import { combine } from '#lib/planner/route.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();

	const HOURS_PER_DAY = 6;
	let days = $derived(Math.max(2, Math.round(data.route.totals.duration_s / 3600 / HOURS_PER_DAY)));
	let stages = $state<Proposal>();
	let busy = $state(false);
	let failed = $state(false);

	const shown = $derived(
		stages
			? stageView(stages)
			: {
					lines: [data.route.legs.flatMap((l) => l.coordinates)],
					profile: combine(data.route.legs),
					breaks: []
				}
	);

	async function propose(ends?: string[]) {
		busy = true;
		failed = false;
		if (ends) days = ends.length + 1;
		const res = await api().POST('/routes/{id}/stages', {
			params: { path: { id: data.route.id }, query: data.token ? { t: data.token } : {} },
			body: { days, ...(ends ? { ends } : {}) }
		});
		busy = false;
		if (res.data) stages = res.data as Proposal;
		else failed = true;
	}
</script>

<Seo title={m.route_split()} index={false} />

<main class="mx-auto w-full max-w-3xl overflow-y-auto px-4 py-8" data-testid="route-split-page">
	<a href={resolve('/routes/[id]', { id: data.route.id })} class="text-sm underline"
		>{data.route.title}</a
	>
	<h1 class="mt-1 font-display text-2xl font-bold">{m.route_split()}</h1>
	<p class="mt-1 text-sm text-stone-600">{m.route_split_intro()}</p>

	<ImportPreview
		lines={shown.lines}
		profile={shown.profile}
		breaks={shown.breaks}
		onpick={stages && !busy
			? (k, lon, lat) => propose(endsWithSpot(stages!, k, lon, lat))
			: undefined}
	/>

	<form
		class="mt-3 flex flex-wrap items-center gap-2 text-sm"
		onsubmit={(e) => {
			e.preventDefault();
			void propose();
		}}
	>
		<label class="flex items-center gap-2">
			{m.import_mode_stages()}
			<input
				type="number"
				min="2"
				max="60"
				class="w-16 rounded-md border border-stone-400 px-2 py-1"
				bind:value={days}
				data-testid="route-split-days"
			/>
			{m.import_mode_stages_unit()}
		</label>
		<button disabled={busy} class={primaryButton}>{m.jplan_submit()}</button>
	</form>

	{#if stages}
		<StageList
			proposal={stages}
			title={data.route.title}
			pace={data.user?.speed_factor ?? 1}
			bind:busy
			onends={propose}
		/>
	{/if}
	{#if failed}
		<p class="mt-3 text-sm text-red-700 dark:text-red-400" role="alert">{m.import_failed()}</p>
	{/if}
</main>
