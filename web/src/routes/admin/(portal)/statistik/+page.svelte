<script lang="ts">
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const t = $derived(data.stats.totals);
	const number = new Intl.NumberFormat('de-CH');
	const week = new Intl.DateTimeFormat('de-CH', {
		day: 'numeric',
		month: 'numeric',
		year: 'numeric'
	});
	const tiles = $derived([
		['Konten', t.accounts],
		['aktiv, 7 Tage', t.active_7],
		['aktiv, 30 Tage', t.active_30],
		['Routen', t.routes],
		['Aufgezeichnet', t.hikes],
		['Etappentouren', t.journeys],
		['Sammlungen', t.collections],
		['Fotos', t.photos],
		['Kommentare', t.comments]
	] as const);
	const columns = [
		['accounts', 'Konten'],
		['routes', 'Routen'],
		['hikes', 'Aufgezeichnet'],
		['journeys', 'Etappentouren'],
		['comments', 'Kommentare']
	] as const;
</script>

<Seo title="Statistik" index={false} />

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<h1 class="mb-6 text-2xl font-semibold">Statistik</h1>

	<dl class="mb-8 grid grid-cols-2 gap-2 sm:grid-cols-3" data-testid="admin-totals">
		{#each tiles as [label, n] (label)}
			<div class="flex flex-col-reverse rounded-lg bg-stone-100 px-3 py-2">
				<dt class="text-xs text-stone-600">{label}</dt>
				<dd class="font-display text-xl font-semibold tabular-nums">{number.format(n)}</dd>
			</div>
		{/each}
	</dl>

	<h2 class="mb-2 font-semibold">Neu pro Woche</h2>
	<div class="overflow-x-auto rounded-xl border border-stone-200 bg-surface">
		<table class="w-full text-sm" data-testid="admin-weeks">
			<thead class="text-left text-xs text-stone-500">
				<tr>
					<th class="px-4 py-2 font-medium">Woche ab</th>
					{#each columns as [, label] (label)}
						<th class="px-4 py-2 text-right font-medium">{label}</th>
					{/each}
				</tr>
			</thead>
			<tbody class="divide-y divide-stone-200">
				{#each data.stats.weeks as w (w.start)}
					<tr>
						<td class="px-4 py-2">{week.format(new Date(w.start))}</td>
						{#each columns as [key] (key)}
							<td class="px-4 py-2 text-right tabular-nums" class:text-stone-400={w[key] === 0}
								>{number.format(w[key])}</td
							>
						{/each}
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
	<p class="mt-2 text-xs text-stone-500">
		Ohne die Konten des Systems (die offiziellen Wanderland-Routen). Aktiv: eingeloggt und Alvyo
		benutzt, auf einen Tag genau.
	</p>
</div>
