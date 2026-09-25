<script lang="ts">
	import { page } from '$app/state';
	import { m } from '$lib/paraglide/messages';

	/** The active tag filter of a list page (`?tag=`), with a way back to all. */
	const tag = $derived(page.url.searchParams.get('tag'));
</script>

{#if tag}
	<p class="mb-3 flex items-center gap-2 text-sm" data-testid="tag-filter">
		<span>{m.tags_filtered({ tag })}</span>
		<a href={page.url.pathname} class="text-accent-ink underline">{m.tags_filter_clear()}</a>
	</p>
{/if}
