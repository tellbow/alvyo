<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '$lib/paraglide/messages';
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { actionButton } from './actions';

	// «⋯»: what is done now and then (printing, collections, deleting …);
	// closes on a click beside it or Escape.
	let { testid, onclose, children }: { testid: string; onclose?: () => void; children: Snippet } =
		$props();

	// A click before hydration would be lost.
	const hydrated = new Hydrated();
	let open = $state(false);
	let box = $state<HTMLElement>();

	function close() {
		open = false;
		onclose?.();
	}
</script>

<svelte:window
	onclick={(e) => {
		// The path as clicked: an item replaced on click is gone from the page by now.
		if (open && box && !e.composedPath().includes(box)) close();
	}}
	onkeydown={(e) => {
		if (e.key === 'Escape' && open) close();
	}}
/>

<div class="relative shrink-0" bind:this={box}>
	<button
		type="button"
		class={actionButton}
		aria-label={m.route_more()}
		aria-expanded={open}
		aria-controls="{testid}-items"
		disabled={!hydrated.value}
		onclick={() => (open ? close() : (open = true))}
		data-testid={testid}>⋯</button
	>
	<div
		id="{testid}-items"
		class="absolute top-11 right-0 z-20 flex w-64 flex-col rounded-xl border border-stone-200 bg-surface p-1.5 text-sm shadow-lg"
		hidden={!open}
	>
		{@render children()}
	</div>
</div>
