<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	// Details on demand: a page's parts as tabs, with their counts; it stays
	// on top while the panel scrolls. The panes are `pane-{id}`.
	let {
		tabs,
		current = $bindable()
	}: { tabs: { id: string; label: string; n?: number }[]; current: string } = $props();

	// A click before hydration would be lost.
	const hydrated = new Hydrated();

	// Tabs as the ARIA pattern has them: one stop for Tab, arrows between.
	function onkeydown(e: KeyboardEvent) {
		const i = tabs.findIndex((t) => t.id === current);
		const next =
			e.key === 'ArrowRight'
				? i + 1
				: e.key === 'ArrowLeft'
					? i - 1
					: e.key === 'Home'
						? 0
						: e.key === 'End'
							? tabs.length - 1
							: undefined;
		if (next === undefined) return;
		e.preventDefault();
		current = tabs[(next + tabs.length) % tabs.length].id;
		document.getElementById(`tab-${current}`)?.focus();
	}
</script>

<div
	class="sticky top-0 z-10 flex shrink-0 [scrollbar-width:none] gap-1 overflow-x-auto overflow-y-hidden border-b border-stone-200 bg-surface px-3 text-sm"
	role="tablist"
	aria-label={m.route_sections()}
	tabindex="-1"
	{onkeydown}
>
	{#each tabs as t (t.id)}
		<button
			type="button"
			role="tab"
			id="tab-{t.id}"
			aria-selected={current === t.id}
			tabindex={current === t.id ? 0 : -1}
			aria-controls="pane-{t.id}"
			disabled={!hydrated.value}
			class="border-b-2 px-1.5 py-2.5 whitespace-nowrap {current === t.id
				? 'border-accent font-semibold text-stone-900'
				: 'border-transparent text-stone-500 hover:text-stone-900'}"
			onclick={() => (current = t.id)}
			data-testid="tab-{t.id}"
		>
			{t.label}{#if t.n !== undefined}<span
					class="ml-1 rounded-full bg-stone-100 px-1.5 text-xs font-normal tabular-nums">{t.n}</span
				>{/if}
		</button>
	{/each}
</div>
