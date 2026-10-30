<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { PUBLIC_GRAFANA_URL } from '$app/env/public';
	import { when } from '#lib/admin/admin.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const sys = $derived(data.system);
	const number = new Intl.NumberFormat('de-CH');
	let checking = $state(false);

	async function again() {
		checking = true;
		await invalidateAll();
		checking = false;
	}
</script>

<Seo title="System" index={false} />

{#snippet dot(ok: boolean)}
	<span
		class="inline-block size-2.5 shrink-0 rounded-full {ok ? 'bg-green-600' : 'bg-red-600'}"
		aria-label={ok ? 'in Ordnung' : 'Problem'}
	></span>
{/snippet}

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<div class="mb-6 flex flex-wrap items-center gap-3">
		<h1 class="flex-1 text-2xl font-semibold">System</h1>
		{#if PUBLIC_GRAFANA_URL}
			<a href={PUBLIC_GRAFANA_URL} class="text-sm underline" target="_blank" rel="noopener"
				>Grafana</a
			>
		{/if}
		<button
			type="button"
			class="rounded-lg border border-stone-300 px-3 py-1.5 text-sm hover:bg-stone-100"
			disabled={checking}
			onclick={again}>{checking ? 'Prüft …' : 'Nochmals prüfen'}</button
		>
	</div>

	<h2 class="mb-2 font-semibold">Dienste</h2>
	<ul
		class="mb-8 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-surface"
		data-testid="admin-services"
	>
		{#each sys.services as s (s.name)}
			<li class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5 text-sm">
				{@render dot(s.up)}
				<span class="flex-1">{s.name}</span>
				<span class="text-stone-500 tabular-nums">{s.ms} ms</span>
				{#if s.detail}<span class="w-full text-xs text-red-700 dark:text-red-400">{s.detail}</span
					>{/if}
			</li>
		{/each}
	</ul>

	<h2 class="mb-2 font-semibold">Daten</h2>
	<ul
		class="mb-8 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-surface"
		data-testid="admin-data"
	>
		{#each sys.data as d (d.name)}
			<li class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5 text-sm">
				{@render dot(!d.stale)}
				<span class="flex-1">{d.name}</span>
				<span class="text-stone-500 tabular-nums">
					{[d.count != null ? number.format(d.count) : '', d.at ? when(d.at) : '']
						.filter(Boolean)
						.join(' · ')}
				</span>
				{#if d.note}<span class="w-full text-xs text-stone-500">{d.note}</span>{/if}
			</li>
		{/each}
	</ul>

	<p class="text-sm text-stone-600">
		Version {sys.version} · Datenbank-Migration {sys.migration}
	</p>
</div>
