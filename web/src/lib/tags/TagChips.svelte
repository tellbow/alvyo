<script lang="ts">
	import { m } from '$lib/paraglide/messages';

	let {
		tags,
		href
	}: {
		tags: string[];
		/** links each tag, e.g. to the list filtered by it */
		href?: (tag: string) => string;
	} = $props();
</script>

{#if tags.length > 0}
	<ul class="flex flex-wrap gap-1" data-testid="tags">
		{#each tags as t (t)}
			<li>
				{#if href}
					<!-- A query on the current page: resolve() does not apply. -->
					<!-- eslint-disable svelte/no-navigation-without-resolve -->
					<a
						href={href(t)}
						title={m.tags_filter_by({ tag: t })}
						class="relative z-10 block rounded-full bg-stone-100 px-2 py-0.5 text-xs text-stone-700 hover:bg-accent-soft"
						>{t}</a
					>
					<!-- eslint-enable svelte/no-navigation-without-resolve -->
				{:else}
					<span class="block rounded-full bg-stone-100 px-2 py-0.5 text-xs text-stone-700">{t}</span
					>
				{/if}
			</li>
		{/each}
	</ul>
{/if}
