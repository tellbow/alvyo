<script lang="ts">
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { onMount, type Snippet } from 'svelte';
	import type { Me, Route } from '#lib/api/client.js';
	import Pois from '#lib/map/Pois.svelte';
	import { m } from '#lib/paraglide/messages.js';
	import ElevationProfile from '#lib/planner/ElevationProfile.svelte';
	import { Planner } from '#lib/planner/planner.svelte.js';
	import type { Profile } from '#lib/planner/route.js';
	import Breakdowns from '#lib/planner/Breakdowns.svelte';
	import StatsPanel from '#lib/planner/StatsPanel.svelte';
	import { intlLocale } from '#lib/util/locale.js';
	import RouteWeather from '#lib/weather/RouteWeather.svelte';
	import SheetMap from './SheetMap.svelte';

	// A page to print on A4 (or save as PDF): map, profile, numbers, places,
	// the weather and connections of the day chosen.
	let {
		route,
		token,
		user,
		heading,
		subtitle = '',
		back,
		date = $bindable(),
		places,
		connections
	}: {
		route: Route;
		token?: string;
		user: Me | null;
		heading: string;
		subtitle?: string;
		/** the page the sheet is of */
		back: string;
		/** YYYY-MM-DD */
		date: string;
		places?: Snippet;
		connections?: Snippet;
	} = $props();

	const planner = new Planner(() => Promise.reject(new Error('read-only')));
	// svelte-ignore state_referenced_locally
	planner.load({ profile: route.profile as Profile, anchors: route.anchors, legs: route.legs });

	const day = $derived(
		new Intl.DateTimeFormat(intlLocale(), { dateStyle: 'full', timeZone: 'UTC' }).format(
			new Date(`${date}T00:00:00Z`)
		)
	);

	// Paper is light: dark text on white also when the site is dark.
	onMount(() => {
		const html = document.documentElement;
		const theme = html.getAttribute('data-theme');
		html.setAttribute('data-theme', 'light');
		return () => {
			if (theme === null) html.removeAttribute('data-theme');
			else html.setAttribute('data-theme', theme);
		};
	});
</script>

<main class="min-h-0 flex-1 overflow-y-auto bg-surface print:overflow-visible">
	<article
		class="mx-auto flex max-w-[190mm] flex-col gap-4 p-4 text-sm [print-color-adjust:exact] print:gap-2 print:p-0 print:text-xs"
		data-testid="sheet"
	>
		<div class="flex flex-wrap items-center gap-3 print:hidden">
			<!-- The page's own address with its share token: resolve() does not apply. -->
			<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
			<a href={back} class="text-accent-ink underline">← {m.sheet_back()}</a>
			<label class="flex items-center gap-1">
				{m.sheet_day()}
				<input
					type="date"
					class="rounded-md border border-stone-400 px-1 py-0.5"
					bind:value={date}
					required
				/>
			</label>
			<button type="button" class="{primaryButtonSmall} ml-auto" onclick={() => print()}
				>{m.sheet_print()}</button
			>
		</div>

		<header>
			<h1 class="text-xl font-semibold" data-testid="sheet-title">{heading}</h1>
			{#if subtitle}<p class="text-stone-600">{subtitle}</p>{/if}
			<p class="text-stone-600" data-testid="sheet-day">{day}</p>
		</header>

		<SheetMap line={planner.line.coordinates} />
		<div class="break-inside-avoid"><ElevationProfile line={planner.line} height={80} /></div>

		<!-- On paper the numbers, places and weather side by side. -->
		<div class="grid gap-6 sm:grid-cols-2 print:grid-cols-3 print:gap-4">
			<div class="flex flex-col gap-3">
				<StatsPanel totals={planner.totals} pace={user?.speed_factor ?? 1} breakdown={false} />
			</div>
			{#if places}<div class="flex flex-col gap-4">{@render places()}</div>{/if}
			<RouteWeather id={route.id} {token} {date} />
		</div>

		<Breakdowns totals={planner.totals} class="grid grid-cols-3 gap-4 [&>*]:mt-0" />
		<Pois id={route.id} {token} />
		{@render connections?.()}
	</article>
</main>
