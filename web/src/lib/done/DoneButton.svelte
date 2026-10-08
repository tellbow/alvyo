<script lang="ts">
	import { api } from '$lib/api/client';
	import { actionButton, menuItem } from '$lib/components/actions';
	import MoreMenu from '$lib/components/MoreMenu.svelte';
	import { m } from '$lib/paraglide/messages';
	import { swissToday } from '$lib/travel/travel';
	import { doneDate } from './done';

	// «Gewandert»: the viewer marks a route or journey as hiked on a day, or
	// takes their mark back; a recorded hike or ticked-off stages (by) count
	// without one.
	let {
		kind,
		id,
		token,
		doneOn,
		marked,
		by
	}: {
		kind: 'routes' | 'journeys';
		id: string;
		token?: string;
		doneOn?: string;
		marked: boolean;
		by: 'hike' | 'stages';
	} = $props();

	const today = swissToday();
	// svelte-ignore state_referenced_locally
	let on = $state(doneOn);
	// svelte-ignore state_referenced_locally
	let isMarked = $state(marked);
	// svelte-ignore state_referenced_locally
	let day = $state(doneOn ?? today);
	let failed = $state(false);

	async function call(mark: boolean) {
		const params = { path: { id }, query: token ? { t: token } : {} };
		const body = { done_on: day };
		// openapi-fetch needs literal paths, hence one branch per kind.
		return kind === 'routes'
			? mark
				? api().PUT('/routes/{id}/done', { params, body })
				: api().DELETE('/routes/{id}/done', { params })
			: mark
				? api().PUT('/journeys/{id}/done', { params, body })
				: api().DELETE('/journeys/{id}/done', { params });
	}

	async function set(mark: boolean, close: () => void) {
		const { data } = await call(mark);
		failed = !data;
		if (!data) return;
		on = data.done_on;
		isMarked = data.done_marked;
		day = on ?? today;
		close();
	}
</script>

<MoreMenu
	testid="done"
	left
	label={on ? `✓ ${doneDate(on)}` : `✓ ${m.done_button()}`}
	ariaLabel={on ? m.done_on({ date: doneDate(on) }) : m.done_button()}
	buttonClass="{actionButton} {on ? 'border-accent bg-accent-soft font-semibold' : ''}"
>
	{#snippet children(close)}
		<label class="flex items-center gap-2 px-2.5 py-2">
			{m.done_day()}
			<input
				type="date"
				max={today}
				bind:value={day}
				class="min-w-0 flex-1 rounded-md border border-stone-400 px-1.5 py-1"
				data-testid="done-day"
			/>
		</label>
		<button
			type="button"
			class="{menuItem} font-medium"
			disabled={!day || day > today}
			onclick={() => set(true, close)}
			data-testid="done-save">✓ {m.done_button()}</button
		>
		{#if on && isMarked}
			<button
				type="button"
				class="{menuItem} text-red-700 dark:text-red-400"
				onclick={() => set(false, close)}
				data-testid="done-remove">{m.done_remove()}</button
			>
		{:else if on}
			<p class="px-2.5 py-1 text-xs text-stone-500">
				{by === 'hike' ? m.done_by_hike() : m.done_by_stages()}
			</p>
		{/if}
		{#if failed}<p class="px-2.5 py-1 text-xs text-red-700 dark:text-red-400" role="alert">
				{m.error_generic()}
			</p>{/if}
	{/snippet}
</MoreMenu>
