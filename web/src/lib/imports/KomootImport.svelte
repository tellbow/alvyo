<script lang="ts">
	import { primaryButton } from '$lib/components/actions';
	import { resolve } from '$app/paths';
	import { SvelteSet } from 'svelte/reactivity';
	import { api } from '$lib/api/client';
	import type { components } from '$lib/api/schema';
	import { m } from '$lib/paraglide/messages';
	import { formatDistance } from '$lib/planner/route';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { intlLocale } from '$lib/util/locale';
	import ImportResult from './ImportResult.svelte';

	type Tour = components['schemas']['KomootTour'];
	type Result = components['schemas']['ImportOutputBody'];

	/** Tours per import request (the API's limit). */
	const BATCH = 10;
	const day = new Intl.DateTimeFormat(intlLocale(), {
		dateStyle: 'medium',
		timeZone: 'Europe/Zurich'
	});
	const hydrated = new Hydrated();

	let email = $state('');
	let password = $state('');
	let session = $state<string>();
	let tours = $state<Tour[]>([]);
	let page = $state(0);
	let totalPages = $state(0);
	const selected = new SvelteSet<number>();
	let busy = $state(false);
	let importing = $state<{ done: number; total: number }>();
	let problem = $state<string>();
	let result = $state<Result>();

	const names = $derived(Object.fromEntries(tours.map((t) => [String(t.id), t.name])));

	async function login(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		problem = undefined;
		const { data, response } = await api().POST('/imports/komoot/login', {
			body: { email: email.trim(), password }
		});
		busy = false;
		password = '';
		if (!data) {
			problem =
				response.status === 422
					? m.komoot_login_failed()
					: response.status === 429
						? m.import_rate()
						: m.komoot_unavailable();
			return;
		}
		session = data.session;
		tours = data.tours;
		totalPages = data.total_pages;
		page = 0;
	}

	function expired() {
		session = undefined;
		tours = [];
		selected.clear();
		problem = m.komoot_expired();
	}

	async function more() {
		busy = true;
		const { data, response } = await api().GET('/imports/komoot/tours', {
			params: { query: { session: session!, page: page + 1 } }
		});
		busy = false;
		if (response.status === 401) return expired();
		if (!data) {
			problem = m.komoot_unavailable();
			return;
		}
		tours = [...tours, ...data.tours];
		totalPages = data.total_pages;
		page += 1;
	}

	function selectAll() {
		for (const t of tours) if (!t.imported_route_id) selected.add(t.id);
	}

	async function run() {
		const ids = [...selected];
		const acc: Result = { routes: [], skipped: [] };
		busy = true;
		problem = undefined;
		result = undefined;
		importing = { done: 0, total: ids.length };
		for (let i = 0; i < ids.length; i += BATCH) {
			const { data, response } = await api().POST('/imports/komoot', {
				body: { session: session!, tour_ids: ids.slice(i, i + BATCH) }
			});
			if (response.status === 401) {
				busy = false;
				importing = undefined;
				return expired();
			}
			if (!data) {
				problem = response.status === 429 ? m.import_rate() : m.import_failed();
				break;
			}
			acc.routes.push(...data.routes);
			acc.skipped.push(...data.skipped);
			for (const r of data.routes) {
				const t = tours.find((t) => String(t.id) === r.ref);
				if (t) t.imported_route_id = r.id;
			}
			importing.done = Math.min(i + BATCH, ids.length);
		}
		busy = false;
		importing = undefined;
		selected.clear();
		result = acc;
	}
</script>

<section class="rounded-md border border-stone-200 bg-surface p-4" data-testid="komoot-import">
	<h2 class="text-lg font-semibold">{m.komoot_title()}</h2>
	<p class="mt-1 text-sm text-stone-600">{m.komoot_intro()}</p>

	{#if !session}
		<form method="post" onsubmit={login} class="mt-3 flex flex-col gap-2 sm:max-w-sm">
			<input
				type="email"
				bind:value={email}
				required
				autocomplete="off"
				placeholder={m.komoot_email()}
				aria-label={m.komoot_email()}
				class="rounded-md border border-stone-400 px-3 py-2 text-sm"
			/>
			<input
				type="password"
				bind:value={password}
				required
				autocomplete="off"
				placeholder={m.komoot_password()}
				aria-label={m.komoot_password()}
				class="rounded-md border border-stone-400 px-3 py-2 text-sm"
			/>
			<button disabled={!hydrated.value || busy} class="{primaryButton} self-start">
				{m.komoot_login()}
			</button>
			<p class="text-xs text-stone-500">{m.komoot_no_password()}</p>
		</form>
	{:else}
		<div class="mt-3 flex flex-wrap items-center gap-3 text-sm">
			<button type="button" class="underline" onclick={selectAll} disabled={busy}
				>{m.komoot_select_all()}</button
			>
			<span class="text-stone-600">{m.komoot_selected({ n: selected.size })}</span>
			<button
				type="button"
				onclick={run}
				disabled={busy || selected.size === 0}
				class="{primaryButton} ml-auto"
			>
				{importing ? m.komoot_importing(importing) : m.import_submit()}
			</button>
		</div>
		{#if tours.length === 0}
			<p class="mt-3 text-sm text-stone-600">{m.komoot_no_tours()}</p>
		{/if}
		<ul class="mt-3 divide-y divide-stone-100 text-sm" data-testid="komoot-tours">
			{#each tours as t (t.id)}
				<li class="flex items-center gap-3 py-1.5">
					{#if t.imported_route_id}
						<a
							href={resolve('/routes/[id]', { id: t.imported_route_id })}
							class="w-24 shrink-0 text-xs text-accent-ink underline">{m.komoot_imported()}</a
						>
					{:else}
						<input
							type="checkbox"
							class="w-24 shrink-0"
							checked={selected.has(t.id)}
							disabled={busy}
							aria-label={t.name}
							onchange={(e) =>
								e.currentTarget.checked ? selected.add(t.id) : selected.delete(t.id)}
						/>
					{/if}
					<span class="flex-1">{t.name}</span>
					<span class="text-xs text-stone-500">
						{t.type === 'tour_recorded' ? m.komoot_recorded() : m.komoot_planned()}
					</span>
					<span class="w-24 text-right text-stone-600 tabular-nums"
						>{day.format(new Date(t.date))}</span
					>
					<span class="w-16 text-right text-stone-600 tabular-nums"
						>{formatDistance(t.distance)}</span
					>
				</li>
			{/each}
		</ul>
		{#if page + 1 < totalPages}
			<button type="button" class="mt-2 text-sm underline" onclick={more} disabled={busy}
				>{m.komoot_more()}</button
			>
		{/if}
	{/if}

	{#if problem}
		<p class="mt-3 text-sm text-red-700 dark:text-red-400" role="alert">{problem}</p>
	{/if}
	{#if result}
		<ImportResult {result} {names} />
	{/if}
</section>
