<script lang="ts">
	import { api } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { addTag, MAX_TAG_LENGTH, MAX_TAGS, sameTag } from './tags';

	let {
		tags = $bindable([]),
		onchange
	}: {
		tags?: string[];
		/** called with the new tags after each change */
		onchange?: (tags: string[]) => void;
	} = $props();

	const uid = $props.id();
	let typed = $state('');
	// The user's own tags, loaded once when the field is first used.
	let mine = $state<string[]>();
	const suggestions = $derived((mine ?? []).filter((s) => !tags.some((t) => sameTag(s, t))));

	async function load() {
		if (mine) return;
		mine = [];
		const { data } = await api().GET('/me/tags');
		mine = data?.tags.map((t) => t.tag) ?? [];
	}

	function set(next: string[]) {
		if (next === tags) return;
		tags = next;
		onchange?.(next);
	}

	function commit() {
		set(addTag(tags, typed));
		typed = '';
	}

	function onkeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' || e.key === ',') {
			e.preventDefault(); // no form submit
			commit();
		} else if (e.key === 'Backspace' && typed === '' && tags.length > 0) {
			set(tags.slice(0, -1));
		}
	}
</script>

<div
	class="flex flex-wrap items-center gap-1 rounded-md border border-stone-300 bg-white px-2 py-1"
	data-testid="tag-input"
>
	{#each tags as t (t)}
		<span
			class="flex items-center gap-0.5 rounded-full bg-stone-100 py-0.5 pr-1 pl-2 text-xs text-stone-700"
			data-testid="tag"
		>
			{t}
			<button
				type="button"
				class="rounded-full px-1 hover:bg-stone-200"
				aria-label={m.tags_remove({ tag: t })}
				onclick={() => set(tags.filter((x) => x !== t))}>×</button
			>
		</span>
	{/each}
	{#if tags.length < MAX_TAGS}
		<input
			class="min-w-24 flex-1 border-0 bg-transparent px-1 py-0.5 text-sm outline-none"
			list="{uid}-suggestions"
			maxlength={MAX_TAG_LENGTH}
			placeholder={m.tags_placeholder()}
			aria-label={m.tags_label()}
			bind:value={typed}
			onfocus={load}
			{onkeydown}
			onchange={commit}
		/>
		<datalist id="{uid}-suggestions">
			{#each suggestions as s (s)}<option value={s}></option>{/each}
		</datalist>
	{/if}
</div>
