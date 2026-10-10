<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Home, type Travel } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';

	/** From which home to the start and back to which after the end, when planning. */
	let { onchange }: { onchange: (travel: Travel) => void } = $props();

	let homes = $state<Home[]>([]);
	let travel = $state<Travel>({});

	onMount(async () => {
		const { data } = await api().GET('/me/homes');
		homes = data?.homes ?? [];
	});

	function set(d: 'to' | 'back', patch: { home_id?: string; time?: string; arrive?: boolean }) {
		const now = travel[d];
		const home = patch.home_id ?? now?.home_id ?? '';
		const next = { ...travel };
		if (home) {
			next[d] = {
				home_id: home,
				time: patch.time ?? now?.time ?? (d === 'to' ? '07:00' : '17:00'),
				arrive: patch.arrive ?? now?.arrive ?? false
			};
		} else delete next[d];
		travel = next;
		onchange(next);
	}
</script>

{#if homes.length > 0}
	<fieldset class="flex flex-col gap-1.5" data-testid="plan-travel">
		<legend class="font-medium">{m.travel_title()}</legend>
		{#each ['to', 'back'] as const as d (d)}
			<div class="flex flex-wrap items-center gap-1">
				<span class="w-20">{d === 'to' ? m.travel_to() : m.travel_back()}</span>
				<select
					class="rounded-md border border-stone-400 px-1 py-0.5"
					aria-label={d === 'to' ? m.travel_from() : m.travel_to_home()}
					value={travel[d]?.home_id ?? ''}
					onchange={(e) => set(d, { home_id: e.currentTarget.value })}
					data-testid="plan-travel-{d}"
				>
					<option value="">{m.travel_none()}</option>
					{#each homes as h (h.id)}
						<option value={h.id}>{h.name}</option>
					{/each}
				</select>
				{#if travel[d]}
					<select
						class="rounded-md border border-stone-400 px-1 py-0.5"
						aria-label={m.connections_mode()}
						value={travel[d]!.arrive}
						onchange={(e) => set(d, { arrive: e.currentTarget.value === 'true' })}
					>
						<option value={false}>{m.connections_depart()}</option>
						<option value={true}>{m.connections_arrive()}</option>
					</select>
					<input
						type="time"
						class="rounded-md border border-stone-400 px-1 py-0.5"
						aria-label={m.connections_time()}
						value={travel[d]!.time}
						onchange={(e) => e.currentTarget.value && set(d, { time: e.currentTarget.value })}
						data-testid="plan-travel-{d}-time"
					/>
				{/if}
			</div>
		{/each}
	</fieldset>
{/if}
