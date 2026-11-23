<script lang="ts">
	import { resolve } from '$app/paths';
	import { cantonName } from '#lib/cantons.js';
	import { getLocale } from '#lib/paraglide/runtime.js';
	import { m } from '#lib/paraglide/messages.js';
	import { sacBackground, sacInk } from '#lib/planner/colors.js';
	import { formatDistance, formatDuration, formatHeight, formatSAC } from '#lib/planner/route.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const canton = $derived(cantonName(data.code, getLocale()));
	const href = (kind: 'route' | 'journey', id: string) =>
		kind === 'route' ? resolve('/routes/[id]', { id }) : resolve('/journeys/[id]', { id });
</script>

<Seo
	title={m.canton_title({ canton })}
	description={m.canton_description({ n: data.items.length, canton })}
	index={data.items.length > 0}
/>

<main class="mx-auto w-full max-w-4xl overflow-y-auto px-4 py-8">
	<a href={resolve('/cantons')} class="text-sm text-stone-600 hover:underline">{m.canton_all()}</a>
	<h1 class="mt-2 text-2xl font-semibold">{m.canton_title({ canton })}</h1>
	{#if data.items.length === 0}
		<p class="mt-4 text-stone-600">{m.canton_empty()}</p>
	{:else}
		<p class="mt-1 text-stone-600">
			{m.canton_description({ n: data.items.length, canton })}
		</p>
		<ul class="mt-6 grid gap-3 sm:grid-cols-2" data-testid="canton-items">
			{#each data.items as it (it.id)}
				<li>
					<a
						href={href(it.kind, it.id)}
						class="block h-full rounded-xl border border-stone-200 bg-surface p-4 hover:border-stone-300 hover:bg-stone-50"
					>
						<div class="flex items-start gap-2">
							<span class="min-w-0 flex-1 truncate font-semibold">{it.title}</span>
							<span
								class="shrink-0 rounded px-1.5 py-0.5 text-xs font-semibold"
								style:background={sacBackground(it.sac_grade)}
								style:color={sacInk(it.sac_grade)}
							>
								{formatSAC(it.sac_grade, it.sac_max)}
							</span>
						</div>
						<div class="mt-1 text-[13px] text-stone-600 tabular-nums">
							{#if it.kind === 'journey'}{m.canton_stages({ n: it.stages })} ·{/if}
							{formatDistance(it.distance_m)} · {formatDuration(it.duration_s)} · ↑&nbsp;{formatHeight(
								it.ascent_m
							)}
						</div>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</main>
