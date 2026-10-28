<script lang="ts">
	import type { Snippet } from 'svelte';
	import Info from '@lucide/svelte/icons/info';
	import { m } from '#lib/paraglide/messages.js';

	// A group of the account's settings. The longer explanation waits behind
	// ⓘ; a collapsed card (for developers) opens on its title.
	let {
		title,
		info,
		collapsed = false,
		danger = false,
		testid,
		class: className = '',
		children
	}: {
		title: string;
		/** One paragraph each. */
		info?: string | string[];
		collapsed?: boolean;
		danger?: boolean;
		testid?: string;
		class?: string;
		children: Snippet;
	} = $props();

	let explained = $state(false);
	const id = $props.id();
</script>

{#snippet heading()}
	<h2 class="text-lg font-semibold {danger ? 'text-red-800 dark:text-red-300' : ''}">{title}</h2>
{/snippet}

{#snippet explanation()}
	{#if info}
		<button
			type="button"
			class="-m-1 rounded-full p-1 text-stone-500 hover:bg-stone-100 hover:text-stone-900"
			aria-label={m.account_info()}
			title={m.account_info()}
			aria-expanded={explained}
			aria-controls="{id}-info"
			onclick={() => (explained = !explained)}
		>
			<Info class="size-4" aria-hidden="true" />
		</button>
	{/if}
{/snippet}

<section
	class="rounded-xl border bg-surface p-5 {danger
		? 'border-red-300 dark:border-red-900'
		: 'border-stone-200'} {className}"
	data-testid={testid}
>
	{#if collapsed}
		<details class="group">
			<summary class="flex cursor-pointer list-none items-center gap-2">
				{@render heading()}
				<span class="ml-auto text-stone-500 group-open:rotate-90" aria-hidden="true">›</span>
			</summary>
			<div class="mt-3">{@render children()}</div>
		</details>
	{:else}
		<div class="flex items-center gap-2">{@render heading()}{@render explanation()}</div>
		{#if info}
			<div
				id="{id}-info"
				class="mt-1 flex flex-col gap-1 text-sm text-stone-600"
				hidden={!explained}
			>
				{#each [info].flat() as p, i (i)}<p>{p}</p>{/each}
			</div>
		{/if}
		<div class="mt-3">{@render children()}</div>
	{/if}
</section>
