<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { PUBLIC_GRAFANA_URL } from '$app/env/public';
	import { refused, when } from '#lib/admin/admin.js';
	import UndoBar from '#lib/admin/UndoBar.svelte';
	import { adminApi } from '#lib/api/client.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const sys = $derived(data.system);
	const number = new Intl.NumberFormat('de-CH');
	let checking = $state(false);
	const isAdmin = $derived(data.user?.role === 'admin');
	let done = $state<{ text: string; logId?: string }>();
	let error = $state('');
	let starting = $state('');

	async function run(name: string) {
		error = '';
		starting = name;
		const { data: r, response } = await adminApi().POST('/admin/jobs/{name}/run', {
			params: { path: { name } }
		});
		starting = '';
		if (!r) return void (error = refused(response.status));
		// A job cannot be taken back; «Verlauf» has it.
		done = { text: `${name} gestartet (${r.job}).` };
		await invalidateAll();
	}

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

	<h2 class="mb-2 font-semibold">Jobs</h2>
	<UndoBar bind:done />
	{#if error}<p role="alert" class="mb-4 text-sm text-red-700 dark:text-red-400">{error}</p>{/if}
	{#if !data.jobs.available}
		<p class="mb-8 text-sm text-stone-600">
			Nur im Cluster, mit ALVYO_ADMIN_JOBS: dort lassen sich die Jobs von Hand starten.
		</p>
	{:else}
		<ul
			class="mb-8 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-surface"
			data-testid="admin-jobs"
		>
			{#each data.jobs.jobs as j (j.name)}
				<li
					class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2.5 text-sm"
					data-testid="admin-job"
				>
					{@render dot(j.running || j.last_finished || !j.last_start)}
					<div class="min-w-0 flex-1">
						<p class="font-medium">{j.name}</p>
						<p class="text-xs text-stone-500">
							{[
								j.suspended ? 'nur von Hand' : j.schedule,
								j.running
									? 'läuft gerade'
									: j.last_start
										? `zuletzt gestartet ${when(j.last_start)}`
										: '',
								j.last_success ? `zuletzt gelungen ${when(j.last_success)}` : ''
							]
								.filter(Boolean)
								.join(' · ')}
						</p>
					</div>
					{#if isAdmin}
						<button
							type="button"
							class="rounded px-2 py-1 ring-1 ring-stone-300 disabled:opacity-50"
							disabled={j.running || starting !== ''}
							onclick={() => run(j.name)}
							>{starting === j.name ? 'Startet …' : 'Jetzt ausführen'}</button
						>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

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
