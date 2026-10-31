<script lang="ts">
	import { resolve } from '$app/paths';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const waiting = $derived(data.reports + data.down.length + data.failed.length);
	const card = 'rounded-xl border border-stone-200 bg-surface p-4';
</script>

<Seo title="Übersicht" index={false} />

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<h1 class="mb-6 text-2xl font-semibold">Übersicht</h1>

	<h2 class="mb-2 font-semibold">Wartet</h2>
	<ul class="mb-8 flex flex-col gap-2 text-sm" data-testid="admin-waiting">
		{#if waiting === 0}
			<li class={card}>Nichts – alles in Ordnung.</li>
		{/if}
		{#if data.reports}
			<li class={card}>
				<a href={resolve('/admin/(portal)/meldungen')} class="font-semibold underline"
					>{data.reports === 1 ? '1 offene Meldung' : `${data.reports} offene Meldungen`}</a
				>
			</li>
		{/if}
		{#if data.down.length}
			<li class={card}>
				<a href={resolve('/admin/(portal)/system')} class="font-semibold underline"
					>Dienste nicht erreichbar:</a
				>
				{data.down.join(', ')}
			</li>
		{/if}
		{#if data.failed.length}
			<li class={card}>
				<a href={resolve('/admin/(portal)/system')} class="font-semibold underline"
					>Jobs zuletzt fehlgeschlagen:</a
				>
				{data.failed.join(', ')}
			</li>
		{/if}
	</ul>

	{#if data.week}
		<h2 class="mb-2 font-semibold">Diese Woche</h2>
		<dl class="grid grid-cols-2 gap-3 sm:grid-cols-5" data-testid="admin-week">
			{#each [['Neue Konten', data.week.accounts], ['Routen', data.week.routes], ['Etappentouren', data.week.journeys], ['Aufgezeichnet', data.week.hikes], ['Kommentare', data.week.comments]] as [label, n] (label)}
				<div class={card}>
					<dd class="text-2xl font-semibold tabular-nums">{n}</dd>
					<dt class="text-xs text-stone-500">{label}</dt>
				</div>
			{/each}
		</dl>
		<a href={resolve('/admin/(portal)/statistik')} class="mt-3 inline-block text-sm underline"
			>Mehr in der Statistik</a
		>
	{/if}
</div>
