<script lang="ts">
	import { api, type RouteWeather } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatHeight } from '$lib/planner/route';
	import { swissToday } from '$lib/travel/travel';
	import { savedAt } from '$lib/util/locale';
	import WeatherIcon from './WeatherIcon.svelte';
	import { climateText, dayLabel, dayText } from './weather';

	// MeteoSwiss's forecast at a route's start, highest point and end: a day
	// chosen from the next ones or any later date (then what is usual in its
	// month), or the one given (YYYY-MM-DD).
	let { id, token, date }: { id: string; token?: string; date?: string } = $props();

	let weather = $state<RouteWeather>();
	let chosen = $state<string>();
	const today = swissToday();
	// A year ahead at most: the normals are by month.
	const last = new Date(Date.now() + 365 * 864e5).toISOString().slice(0, 10);
	const day = $derived(date ?? chosen);

	const dates = $derived(weather?.places[0]?.days.map((d) => d.date) ?? []);
	// Asked again only for a day beyond the forecast.
	const asked = $derived(day && day > today && !dates.includes(day) ? day : undefined);
	$effect(() => {
		let stale = false;
		api()
			.GET('/routes/{id}/weather', {
				params: {
					path: { id },
					query: { ...(token ? { t: token } : {}), ...(asked ? { date: asked } : {}) }
				}
			})
			.then(({ data }) => {
				if (!stale && data) weather = data;
			});
		return () => {
			stale = true;
		};
	});

	const shown = $derived(day ?? dates[0]);
	const climate = $derived(weather?.places.find((p) => p.climate)?.climate);
	const role = (r: string) =>
		r === 'start' ? m.weather_start() : r === 'top' ? m.weather_top() : m.weather_end();
</script>

{#if weather && (dates.length > 0 || climate)}
	<section class="flex flex-col gap-2 text-sm" data-testid="weather">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
			{m.weather_title()}{#if date}, {dayLabel(date)}{/if}
		</h3>
		{#if !date}
			<div class="flex flex-wrap items-center gap-1" role="group" aria-label={m.weather_title()}>
				{#each dates as d, i (d)}
					<button
						type="button"
						class="rounded-full px-2 py-0.5 text-xs ring-1 ring-stone-300 {d === shown
							? 'bg-accent text-on-accent ring-0'
							: 'hover:bg-stone-100'}"
						aria-pressed={d === shown}
						onclick={() => (chosen = d)}>{i === 0 ? m.weather_today() : dayLabel(d)}</button
					>
				{/each}
				<label class="flex items-center gap-1 text-xs">
					<span class="sr-only">{m.weather_other_day()}</span>
					<input
						type="date"
						min={today}
						max={last}
						value={shown}
						class="rounded-full px-2 py-0.5 text-xs ring-1 ring-stone-300 {shown &&
						!dates.includes(shown)
							? 'bg-accent text-on-accent ring-0'
							: ''}"
						aria-label={m.weather_other_day()}
						data-testid="weather-date"
						onchange={(e) => {
							const v = e.currentTarget.value;
							if (v >= today) chosen = v;
						}}
					/>
				</label>
			</div>
		{/if}
		<ul class="flex flex-col gap-1.5">
			{#each weather.places as p (p.roles.join())}
				{@const forecast = p.days.find((d) => d.date === shown)}
				{#if forecast || (p.climate && shown && !dates.includes(shown))}
					<li class="flex items-start gap-2" data-testid="weather-place">
						{#if forecast}<WeatherIcon code={forecast.symbol} />{/if}
						<span>
							<span class="font-medium">{p.roles.map(role).join(', ')}</span>
							<span class="text-stone-500">· {p.point.name}, {formatHeight(p.point.height)}</span>
							<br />{#if forecast}{dayText(forecast)}{:else if p.climate}{climateText(
									p.climate,
									Number(shown!.slice(0, 4))
								)}{/if}
						</span>
					</li>
				{/if}
			{/each}
		</ul>
		{#if climate && shown && !dates.includes(shown)}
			<p class="text-xs text-stone-500" data-testid="weather-climate-source">
				{m.weather_climate_source({ station: climate.station, rain: climate.rain_station })}
			</p>
		{:else}
			<p class="text-xs text-stone-500">{m.weather_source({ time: savedAt(weather.run) })}</p>
		{/if}
	</section>
{/if}
