<script lang="ts">
	import { api, type JourneyWeather } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatHeight } from '$lib/planner/route';
	import { savedAt } from '$lib/util/locale';
	import { dayLabel, dayText } from './weather';

	// The forecast at each stage's highest point for its planned day, for the
	// stages planned in the next nine days; `key` changes when stages do.
	let { id, token, key }: { id: string; token?: string; key: string } = $props();

	let weather = $state<JourneyWeather>();
	$effect(() => {
		void key;
		let stale = false;
		api()
			.GET('/journeys/{id}/weather', { params: { path: { id }, query: token ? { t: token } : {} } })
			.then(({ data }) => {
				if (!stale) weather = data;
			});
		return () => {
			stale = true;
		};
	});
	const planned = $derived(weather?.stages.filter((s) => s.day) ?? []);
</script>

{#if weather && planned.length > 0}
	<section class="flex flex-col gap-1 text-sm" data-testid="journey-weather">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.weather_title()}</h3>
		<ul class="flex flex-col gap-1">
			{#each planned as s (s.stage)}
				<li data-testid="stage-weather">
					<span class="font-medium"
						>{m.weather_stage({ n: s.stage, date: dayLabel(s.day!.date) })}</span
					>
					<span class="text-stone-500">· {s.point.name}, {formatHeight(s.point.height)}</span>
					<br />{dayText(s.day!)}
				</li>
			{/each}
		</ul>
		<p class="text-xs text-stone-500">{m.weather_source({ time: savedAt(weather.run) })}</p>
	</section>
{/if}
