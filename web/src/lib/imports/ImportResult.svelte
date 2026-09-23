<script lang="ts">
	import { resolve } from '$app/paths';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';

	type Result = components['schemas']['ImportOutputBody'];
	type Reason = components['schemas']['Skipped']['reason'];

	let {
		result,
		names = {}
	}: {
		result: Result;
		/** Display names for skipped entries named by id (Komoot tours). */
		names?: Record<string, string>;
	} = $props();

	const reasons: Record<Reason, () => string> = {
		outside: m.import_reason_outside,
		short: m.import_reason_short,
		elevation: m.import_reason_elevation,
		duplicate: m.import_reason_duplicate,
		other: m.import_reason_other
	};
</script>

<div class="mt-4 flex flex-col gap-2 text-sm" data-testid="import-result">
	{#if result.journey_id}
		<p>
			<a
				href={resolve('/journeys/[id]', { id: result.journey_id })}
				class="font-medium text-emerald-800 underline">{m.import_journey_created()}</a
			>
		</p>
	{:else if result.routes.length > 0}
		<p>{m.import_routes_created()}</p>
		<ul class="list-inside list-disc">
			{#each result.routes as r (r.id)}
				<li>
					<a href={resolve('/routes/[id]', { id: r.id })} class="text-emerald-800 underline"
						>{r.title}</a
					>
				</li>
			{/each}
		</ul>
	{/if}
	{#if result.skipped.length > 0}
		<p class="text-stone-700">{m.import_skipped()}</p>
		<ul class="list-inside list-disc text-stone-600" data-testid="import-skipped">
			{#each result.skipped as s, i (i)}
				<li>{names[s.name] ?? s.name}: {reasons[s.reason]()}</li>
			{/each}
		</ul>
	{/if}
</div>
