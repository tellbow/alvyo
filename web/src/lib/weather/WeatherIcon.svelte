<script lang="ts">
	import { weatherSymbol } from './weather';
	import { WEATHER_ICONS } from './weather';

	// MeteoSwiss's symbol as our icon, with MeteoSwiss's words for it.
	let { code, size = 28 }: { code?: number; size?: number } = $props();
	const symbol = $derived(weatherSymbol(code));
</script>

{#if symbol}
	<svg
		width={size}
		height={size}
		viewBox="0 0 24 24"
		role="img"
		aria-label={symbol.text}
		class="shrink-0"
		data-testid="weather-icon"
	>
		<title>{symbol.text}</title>
		{#each WEATHER_ICONS[symbol.icon] as layer, i (i)}
			<path fill={layer.color} d={layer.path} />
		{/each}
	</svg>
{/if}
