<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type RouteWeather } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { formatHeight } from '$lib/planner/route';
	import { savedAt } from '$lib/util/locale';
	import { dayLabel, dayText } from './weather';

	// MeteoSwiss's forecast at a route's start, highest point and end: a day
	// chosen from the next ones, or the one given (YYYY-MM-DD).
	let { id, token, date }: { id: string; token?: string; date?: string } = $props();

	let weather = $state<RouteWeather>();
	let chosen = $state(0);

	onMount(async () => {
		const { data } = await api().GET('/routes/{id}/weather', {
			params: { path: { id }, query: token ? { t: token } : {} }
		});
		weather = data;
	});

	const all = $derived(weather?.places[0]?.days.map((d) => d.date) ?? []);
	const dates = $derived(date ? all.filter((d) => d === date) : all);
	const role = (r: string) =>
		r === 'start' ? m.weather_start() : r === 'top' ? m.weather_top() : m.weather_end();
</script>

{#if weather && dates.length > 0}
	<section class="flex flex-col gap-2 text-sm" data-testid="weather">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
			{m.weather_title()}{#if date}, {dayLabel(date)}{/if}
		</h3>
		<div class="flex flex-wrap gap-1" role="group" aria-label={m.weather_title()} hidden={!!date}>
			{#each dates as date, i (date)}
				<button
					type="button"
					class="rounded-full px-2 py-0.5 text-xs ring-1 ring-stone-300 {i === chosen
						? 'bg-accent text-on-accent ring-0'
						: 'hover:bg-stone-100'}"
					aria-pressed={i === chosen}
					onclick={() => (chosen = i)}>{i === 0 ? m.weather_today() : dayLabel(date)}</button
				>
			{/each}
		</div>
		<ul class="flex flex-col gap-1">
			{#each weather.places as p (p.roles.join())}
				{@const day = p.days.find((d) => d.date === dates[chosen])}
				{#if day}
					<li data-testid="weather-place">
						<span class="font-medium">{p.roles.map(role).join(', ')}</span>
						<span class="text-stone-500">· {p.point.name}, {formatHeight(p.point.height)}</span>
						<br />{dayText(day)}
					</li>
				{/if}
			{/each}
		</ul>
		<p class="text-xs text-stone-500">{m.weather_source({ time: savedAt(weather.run) })}</p>
	</section>
{/if}
