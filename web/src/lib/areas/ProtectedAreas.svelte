<script lang="ts">
	import type { ProtectedArea } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { getLocale } from '#lib/paraglide/runtime.js';
	import { intlLocale } from '#lib/util/locale.js';
	import { inPeriod, periodDay, ruleText } from './areas';
	import HintPopup from './HintPopup.svelte';

	let {
		areas,
		failed = false,
		days = []
	}: {
		/** The areas crossed; undefined while loading. */
		areas?: ProtectedArea[];
		failed?: boolean;
		/** Planned days (YYYY-MM-DD) of the hike, to say when a rule applies then. */
		days?: string[];
	} = $props();

	const today = new Date();
	const applies = (a: ProtectedArea) =>
		!a.period || inPeriod(a.period, today)
			? 'now'
			: days.some((d) => inPeriod(a.period!, d))
				? 'planned'
				: undefined;
	const note = $derived(
		areas?.some((a) => applies(a) === 'now')
			? m.areas_now()
			: areas?.some((a) => applies(a) === 'planned')
				? m.areas_on_date()
				: undefined
	);
</script>

{#if failed}
	<p class="text-xs text-stone-500" data-testid="areas-failed">{m.areas_failed()}</p>
{:else if areas && areas.length > 0}
	<HintPopup title={m.areas_title()} count={areas.length} {note} testid="protected-areas">
		<ul class="flex flex-col gap-2">
			{#each areas as a (a.kind + a.id)}
				{@const now = !a.period || inPeriod(a.period, today)}
				{@const planned = a.period ? days.some((d) => inPeriod(a.period!, d)) : days.length > 0}
				<li
					class="rounded-md border px-2 py-1.5 {now || planned
						? 'border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/40'
						: 'border-stone-200'}"
					data-testid="protected-area"
				>
					<p>
						<span class="font-medium">{a.name}</span>
						<span class="text-xs text-stone-500">
							· {a.kind === 'wildlife_rest'
								? m.areas_kind_wildlife_rest()
								: m.areas_kind_hunting_reserve()}
							· {a.binding ? m.areas_binding() : m.areas_recommended()}
						</span>
					</p>
					<p class="text-xs">
						{[
							ruleText(a, getLocale()),
							a.period &&
								m.areas_period({
									from: periodDay(a.period.from, intlLocale()),
									to: periodDay(a.period.to, intlLocale())
								}),
							a.stages?.length && m.areas_stages({ list: a.stages.join(', ') })
						]
							.filter(Boolean)
							.join(' · ')}
					</p>
					{#if a.note}<p class="text-xs text-stone-600">{a.note}</p>{/if}
					<p class="text-xs">
						{#if a.period && now}<span class="font-medium text-amber-800 dark:text-amber-200"
								>{m.areas_now()}</span
							>
						{:else if a.period && planned}<span
								class="font-medium text-amber-800 dark:text-amber-200">{m.areas_on_date()}</span
							>{/if}
						{#if a.link}
							<!-- The canton's or BAFU's page: resolve() does not apply. -->
							<!-- eslint-disable svelte/no-navigation-without-resolve -->
							<a
								href={a.link}
								target="_blank"
								rel="noopener noreferrer nofollow"
								class="text-accent-ink underline">{m.areas_more()} ↗</a
							>
							<!-- eslint-enable svelte/no-navigation-without-resolve -->
						{/if}
					</p>
				</li>
			{/each}
		</ul>
		<p class="text-xs text-stone-500">{m.areas_source()}</p>
	</HintPopup>
{/if}
