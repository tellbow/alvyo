<script lang="ts">
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import X from '@lucide/svelte/icons/x';
	import MoreMenu from '#lib/components/MoreMenu.svelte';
	import { menuItem } from '#lib/components/actions.js';
	import { m } from '#lib/paraglide/messages.js';
	import { focused } from '#lib/util/focus.js';

	// A list row's «⋯»: deleting one's own (asked again) or removing a shared
	// one from one's list (feedback issue 45).
	let {
		testid,
		title,
		onremove,
		confirm,
		leave = false
	}: {
		testid: string;
		/** The row's, for the button's label. */
		title: string;
		onremove: () => void;
		/** Asked before deleting. */
		confirm?: string;
		/** Shared with the viewer: removes it from their list only. */
		leave?: boolean;
	} = $props();

	let asking = $state(false);
</script>

<!-- Above the row's link. -->
<div class="relative">
	<MoreMenu
		{testid}
		ariaLabel="{m.route_more()}: {title}"
		buttonClass="inline-flex size-9 items-center justify-center rounded-lg text-stone-500 hover:bg-stone-100 hover:text-stone-800"
		onclose={() => (asking = false)}
	>
		{#snippet children(close)}
			{#if leave}
				<button
					type="button"
					class="{menuItem} items-center gap-2"
					data-testid="{testid}-leave"
					onclick={() => {
						close();
						onremove();
					}}><X class="size-4" aria-hidden="true" />{m.shared_remove_mine()}</button
				>
			{:else if asking}
				<button
					type="button"
					class="flex w-full items-center gap-2 rounded-lg bg-red-700 px-2.5 py-2 text-left font-semibold text-white hover:bg-red-800"
					use:focused
					data-testid="{testid}-delete-confirm"
					onclick={() => {
						close();
						onremove();
					}}><Trash2 class="size-4" aria-hidden="true" />{confirm}</button
				>
			{:else}
				<button
					type="button"
					class="{menuItem} items-center gap-2 text-red-700 dark:text-red-400"
					data-testid="{testid}-delete"
					onclick={() => (asking = true)}
					><Trash2 class="size-4" aria-hidden="true" />{m.route_delete()}</button
				>
			{/if}
		{/snippet}
	</MoreMenu>
</div>
