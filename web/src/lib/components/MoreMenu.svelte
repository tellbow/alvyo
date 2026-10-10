<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/paraglide/messages.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { actionButton } from './actions';

	// «⋯»: what is done now and then (printing, collections, deleting …);
	// closes on a click beside it or Escape. With another label and button
	// style a small popover of its own (opening at the button's left edge).
	let {
		testid,
		label = '⋯',
		ariaLabel = m.route_more(),
		buttonClass = actionButton,
		left = false,
		onclose,
		children
	}: {
		testid: string;
		label?: string;
		ariaLabel?: string;
		buttonClass?: string;
		left?: boolean;
		onclose?: () => void;
		children: Snippet<[close: () => void]>;
	} = $props();

	// A click before hydration would be lost.
	const hydrated = new Hydrated();
	let open = $state(false);
	let box = $state<HTMLElement>();
	let trigger = $state<HTMLButtonElement>();

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
		if (e.key === 'Escape' && open) {
			close();
			trigger?.focus(); // back where the keyboard was
		}
	}}
/>

<div class="relative shrink-0" bind:this={box}>
	<button
		bind:this={trigger}
		type="button"
		class={buttonClass}
		aria-label={ariaLabel}
		aria-expanded={open}
		aria-controls="{testid}-items"
		disabled={!hydrated.value}
		onclick={() => (open ? close() : (open = true))}
		data-testid={testid}>{label}</button
	>
	<div
		id="{testid}-items"
		class="absolute top-11 z-20 flex w-64 flex-col rounded-xl border border-stone-200 bg-surface p-1.5 text-sm shadow-lg {left
			? 'left-0'
			: 'right-0'}"
		hidden={!open}
	>
		{@render children(close)}
	</div>
</div>
