<script lang="ts">
	import { api, type JourneyReminders } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { dayLabel } from '$lib/weather/weather';

	// Reminders by e-mail before the journey starts (to book the nights, the
	// weather, the day before), for the owner and the people who come along;
	// each turns theirs on or off. `key` changes when the stages' days do.
	let { id, key }: { id: string; key: string } = $props();

	let r = $state<JourneyReminders>();
	$effect(() => {
		void key;
		let stale = false;
		api()
			.GET('/journeys/{id}/reminders', { params: { path: { id } } })
			.then(({ data }) => {
				if (!stale) r = data;
			});
		return () => {
			stale = true;
		};
	});

	async function set(on: boolean) {
		const { data } = await api().PUT('/journeys/{id}/reminders', {
			params: { path: { id } },
			body: { on }
		});
		if (data) r = data;
	}

	const what = (kind: string) =>
		kind === 'book'
			? m.reminders_book()
			: kind === 'weather'
				? m.reminders_weather()
				: m.reminders_start();
</script>

{#if r?.start}
	<section class="flex flex-col gap-1 text-sm" data-testid="journey-reminders">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
			{m.reminders_title()}
		</h3>
		<label class="flex items-center gap-2">
			<input
				type="checkbox"
				checked={r.on}
				onchange={(e) => set(e.currentTarget.checked)}
				data-testid="reminders-on"
			/>
			{m.reminders_on()}
		</label>
		{#if r.on && r.upcoming.length > 0}
			<ul class="text-xs text-stone-600">
				{#each r.upcoming as u (u.kind)}
					<li>{dayLabel(u.day)}: {what(u.kind)}</li>
				{/each}
			</ul>
		{/if}
		<p class="text-xs text-stone-500">{m.reminders_hint()}</p>
	</section>
{/if}
