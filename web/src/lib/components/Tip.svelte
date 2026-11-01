<script lang="ts">
	import type { Snippet } from 'svelte';
	import * as Tooltip from '#lib/components/ui/tooltip/index.js';

	// A hint on hover for an icon-only button, which keeps its aria-label; the
	// span is no tab stop of its own (feedback issue 56).
	let {
		text,
		class: className = '',
		children
	}: {
		text: string;
		/** Where the button sits among its neighbours: the span is what they see. */
		class?: string;
		children: Snippet;
	} = $props();
</script>

<Tooltip.Provider delayDuration={300}>
	<Tooltip.Root>
		<Tooltip.Trigger>
			{#snippet child({ props })}
				<span {...{ ...props, tabindex: -1 }} class="inline-flex {className}"
					>{@render children()}</span
				>
			{/snippet}
		</Tooltip.Trigger>
		<Tooltip.Content>{text}</Tooltip.Content>
	</Tooltip.Root>
</Tooltip.Provider>
