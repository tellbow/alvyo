<script lang="ts">
	import type { SnowAlong } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { formatDistance } from '#lib/planner/route.js';
	import { intlLocale } from '#lib/util/locale.js';
	import { roughly } from './areas';
	import HintPopup from './HintPopup.svelte';

	let {
		snow,
		onshow
	}: {
		/** The snow along the line; undefined while loading or failed. */
		snow?: SnowAlong;
		/** Shows a stretch on the map. */
		onshow?: (parts: number[][][]) => void;
	} = $props();

	const len = (metres: number) => formatDistance(roughly(metres));
	const steep = $derived(!!snow && snow.slopes && snow.steep_m > 0);
	const day = (d: string) =>
		new Intl.DateTimeFormat(intlLocale(), {
			day: 'numeric',
			month: 'long',
			timeZone: 'UTC'
		}).format(new Date(`${d}T00:00:00Z`));
</script>

{#snippet credit(text: string)}
	<p class="text-xs text-stone-500">
		<!-- The data's own page: resolve() does not apply. -->
		<!-- eslint-disable svelte/no-navigation-without-resolve -->
		<a
			href="https://land.copernicus.eu/en/products/snow"
			target="_blank"
			rel="noopener noreferrer"
			class="underline">{text}</a
		>
		<!-- eslint-enable svelte/no-navigation-without-resolve -->
	</p>
{/snippet}

{#if snow?.date && snow.snow_m > 0}
	<HintPopup
		title={m.snow_along_title()}
		count={snow.stretches.length}
		note={steep
			? m.snow_along_note_steep({ snow: len(snow.snow_m), steep: len(snow.steep_m) })
			: m.snow_along_note({ snow: len(snow.snow_m) })}
		testid="snow-along"
	>
		{#snippet children(close)}
			<p data-testid="snow-along-summary">
				{steep
					? m.snow_along_summary_steep({ snow: len(snow.snow_m), steep: len(snow.steep_m) })
					: m.snow_along_summary({ snow: len(snow.snow_m) })}
				{#if snow.patches_m > 0}{m.snow_along_patches({ distance: len(snow.patches_m) })}{/if}
			</p>
			<ul class="flex flex-col gap-2">
				{#each snow.stretches as s, i (i)}
					<li
						class="rounded-md border px-2 py-1.5 {snow.slopes && s.steep_m > 0
							? 'border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/40'
							: 'border-stone-200'}"
						data-testid="snow-stretch"
					>
						<p class="text-xs">
							{[
								s.stage && m.areas_stages({ list: String(s.stage) }),
								m.snow_along_stretch({
									at: formatDistance(s.from_m),
									length: len(s.to_m - s.from_m)
								}),
								snow.slopes &&
									s.steep_m > 0 &&
									m.snow_along_stretch_steep({ steep: len(s.steep_m) })
							]
								.filter(Boolean)
								.join(' · ')}
						</p>
						{#if onshow && s.line.length >= 2}
							<button
								type="button"
								class="text-xs text-accent-ink underline"
								onclick={() => {
									close();
									onshow([s.line]);
								}}
								data-testid="snow-stretch-show">{m.show_on_map()}</button
							>
						{/if}
					</li>
				{/each}
			</ul>
			<p class="text-xs text-stone-600">
				{m.snow_date({ date: day(snow.date!) })}. {m.snow_along_limits()}
			</p>
			<p class="text-xs">{m.snow_hint()}</p>
			{@render credit(snow.attribution)}
		{/snippet}
	</HintPopup>
{:else if snow?.date && snow.patches_m > 0}
	<section class="flex flex-col gap-1 text-sm" data-testid="snow-along">
		<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">
			{m.snow_along_title()}
		</h3>
		<p class="text-xs">
			{m.snow_along_patches_only({ distance: len(snow.patches_m), date: day(snow.date) })}
		</p>
		{@render credit(snow.attribution)}
	</section>
{/if}
