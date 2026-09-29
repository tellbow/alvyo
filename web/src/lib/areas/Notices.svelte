<script lang="ts">
	import type { Notice } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { getLocale } from '$lib/paraglide/runtime';
	import { intlLocale } from '$lib/util/locale';
	import { noticeText, shootingDay, touches } from './areas';
	import HintPopup from './HintPopup.svelte';

	let {
		notices,
		days = []
	}: {
		/** Closed trails and shooting on the way; undefined while loading. */
		notices?: Notice[];
		/** Planned days (YYYY-MM-DD) of the hike; today otherwise. */
		days?: string[];
	} = $props();

	const today = new Date().toLocaleDateString('sv', { timeZone: 'Europe/Zurich' });
	const when = $derived(days.length > 0 ? days : [today]);
	const urgent = $derived(notices?.some((n) => touches(n, when)));
</script>

{#if notices && notices.length > 0}
	<HintPopup
		title={m.notices_title()}
		count={notices.length}
		note={urgent ? (days.length > 0 ? m.areas_on_date() : m.areas_now()) : undefined}
		testid="notices"
	>
		<ul class="flex flex-col gap-2">
			{#each notices as n (n.kind + n.id)}
				<li
					class="rounded-md border px-2 py-1.5 {touches(n, when)
						? 'border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/40'
						: 'border-stone-200'}"
					data-testid="notice"
				>
					<p>
						<span class="font-medium">{noticeText(n.title, getLocale())}</span>
						<span class="text-xs text-stone-500">
							· {n.kind === 'closure' ? m.notices_closure() : m.notices_shooting()}</span
						>
					</p>
					<p class="text-xs">
						{[
							n.reason && noticeText(n.reason, getLocale()),
							n.from &&
								n.to &&
								m.notices_period({
									from: shootingDay(n.from, intlLocale()),
									to: shootingDay(n.to, intlLocale())
								}),
							n.days
								?.map((d) =>
									d.from && d.to
										? m.notices_day_hours({
												day: shootingDay(d.date, intlLocale()),
												from: `${d.from.slice(0, 2)}:${d.from.slice(2)}`,
												to: `${d.to.slice(0, 2)}:${d.to.slice(2)}`
											})
										: shootingDay(d.date, intlLocale())
								)
								.join(', '),
							n.stages?.length && m.areas_stages({ list: n.stages.join(', ') })
						]
							.filter(Boolean)
							.join(' · ')}
					</p>
					{#if n.phone || n.link}
						<p class="text-xs">
							{#if n.phone}<a
									href="tel:{n.phone.replaceAll(' ', '')}"
									class="text-accent-ink underline">{n.phone}</a
								>{/if}
							{#if n.link}
								<!-- The army's page: resolve() does not apply. -->
								<!-- eslint-disable svelte/no-navigation-without-resolve -->
								<a
									href={noticeText(n.link, getLocale())}
									target="_blank"
									rel="noopener noreferrer nofollow"
									class="ml-2 text-accent-ink underline">{m.areas_more()} ↗</a
								>
								<!-- eslint-enable svelte/no-navigation-without-resolve -->
							{/if}
						</p>
					{/if}
				</li>
			{/each}
		</ul>
		<p class="text-xs text-stone-500">{m.notices_source()}</p>
	</HintPopup>
{/if}
