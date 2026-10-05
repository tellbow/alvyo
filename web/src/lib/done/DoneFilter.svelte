<script lang="ts">
	import { page } from '$app/state';
	import { SvelteURLSearchParams } from 'svelte/reactivity';
	import { m } from '$lib/paraglide/messages';
	import { readDone, type DoneFilter } from './done';

	// All, planned or hiked, kept in the page address (`?done=`) with the
	// other filters.
	const current = $derived(readDone(page.url.searchParams));
	const href = (v: DoneFilter) => {
		const q = new SvelteURLSearchParams(page.url.search);
		if (v) q.set('done', v);
		else q.delete('done');
		const s = q.toString();
		return page.url.pathname + (s ? `?${s}` : '');
	};
	const options: [DoneFilter, () => string][] = [
		['', m.done_filter_all],
		['planned', m.done_filter_planned],
		['done', m.done_filter_done]
	];
</script>

<nav
	class="mb-4 inline-flex rounded-lg bg-stone-100 p-0.5 text-sm"
	aria-label={m.done_filter()}
	data-testid="done-filter"
>
	{#each options as [v, label] (v)}
		<!-- The same page with another query: resolve() does not apply. -->
		<!-- eslint-disable svelte/no-navigation-without-resolve -->
		<a
			href={href(v)}
			aria-current={current === v ? 'page' : undefined}
			class="rounded-md px-3 py-1 {current === v
				? 'bg-surface font-semibold shadow-sm'
				: 'text-stone-600 hover:text-stone-900'}">{label()}</a
		>
		<!-- eslint-enable svelte/no-navigation-without-resolve -->
	{/each}
</nav>
