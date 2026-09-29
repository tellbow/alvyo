<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '$lib/paraglide/messages';

	// A line with how many there are, the list itself in a popup: shown on
	// request, not always in full.
	let {
		title,
		count,
		note,
		testid,
		children
	}: {
		title: string;
		count: number;
		/** Said beside the count and highlighted, e.g. «gilt jetzt». */
		note?: string;
		testid: string;
		children: Snippet;
	} = $props();

	let dialog = $state<HTMLDialogElement>();
</script>

<section class="flex flex-col gap-1 text-sm" data-testid={testid}>
	<h3 class="text-xs font-medium tracking-wide text-stone-500 uppercase">{title}</h3>
	<button
		type="button"
		class="flex items-center gap-2 self-start rounded-md border px-2 py-1 text-left {note
			? 'border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/40'
			: 'border-stone-200'}"
		aria-haspopup="dialog"
		onclick={() => dialog?.showModal()}
		data-testid="{testid}-open"
	>
		<span class="underline">{m.hints_open({ count })}</span>
		{#if note}<span class="text-xs font-medium text-amber-800 dark:text-amber-200">{note}</span
			>{/if}
	</button>
</section>

<dialog
	bind:this={dialog}
	class="m-auto max-h-[85dvh] w-[min(36rem,calc(100vw-2rem))] rounded-lg bg-surface p-0 text-stone-900 shadow-xl backdrop:bg-black/40"
	aria-label={title}
	onclick={(e) => {
		if (e.target === dialog) dialog.close(); // a click beside the box
	}}
>
	<div class="flex flex-col gap-3 p-4 text-sm" data-testid="{testid}-popup">
		<div class="flex items-start gap-2">
			<h2 class="flex-1 text-base font-semibold">{title}</h2>
			<button
				type="button"
				class="-mt-1 px-2 text-2xl leading-none"
				onclick={() => dialog?.close()}
				aria-label={m.place_close()}>×</button
			>
		</div>
		{@render children()}
	</div>
</dialog>
