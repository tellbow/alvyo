<script lang="ts">
	import { api, type JourneyWeather } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatHeight } from '#lib/planner/route.js';
	import { savedAt } from '#lib/util/locale.js';
	import WeatherIcon from './WeatherIcon.svelte';
	import { climateText, dayLabel, dayText } from './weather';

	// The forecast at each stage's highest point for its planned day, for the
	// stages planned in the next nine days, and what is usual in its month
	// for those planned later; `key` changes when stages do.
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
	const planned = $derived(weather?.stages.filter((s) => s.day || s.climate) ?? []);
	const climate = $derived(planned.find((s) => s.climate)?.climate);
</script>

{#if weather && planned.length > 0}
	<section class="flex flex-col gap-1 text-sm" data-testid="journey-weather">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{m.weather_title()}</h3>
		<ul class="flex flex-col gap-1">
			{#each planned as s (s.stage)}
				<li class="flex items-start gap-2" data-testid="stage-weather">
					{#if s.day}<WeatherIcon code={s.day.symbol} />{/if}
					<span>
						<span class="font-medium"
							>{m.weather_stage({
								n: s.stage,
								date: dayLabel(s.day?.date ?? s.planned_date!)
							})}</span
						>
						<span class="text-stone-500">· {s.point.name}, {formatHeight(s.point.height)}</span>
						<br />{#if s.day}{dayText(s.day)}{:else if s.climate}{climateText(
								s.climate,
								Number(s.planned_date!.slice(0, 4))
							)}{/if}
					</span>
				</li>
			{/each}
		</ul>
		<p class="text-xs text-stone-500">{m.weather_source({ time: savedAt(weather.run) })}</p>
		{#if climate}
			<p class="text-xs text-stone-500">
				{m.weather_climate_source({ station: climate.station, rain: climate.rain_station })}
			</p>
		{/if}
	</section>
{/if}
