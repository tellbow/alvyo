<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/paraglide/messages.js';

	// What the points' colours mean and what to do with them (feedback issue
	// 88): open until hidden, remembered in this browser; undefined until
	// read, so it does not flash.
	const KEY = 'alvyo.planHelpHidden';
	let open = $state<boolean>();
	onMount(() => {
		try {
			open = localStorage.getItem(KEY) !== '1';
		} catch {
			open = true; // storage blocked
		}
	});

	function show(on: boolean) {
		open = on;
		try {
			localStorage.setItem(KEY, on ? '0' : '1');
		} catch {
			// storage blocked: the choice lasts for this page
		}
	}
</script>

{#if open}
	<section data-testid="plan-help" class="rounded-md bg-stone-100 p-3 text-sm">
		<div class="mb-2 flex items-center justify-between gap-2">
			<h2 class="font-medium">{m.plan_help_title()}</h2>
			<button type="button" class="text-xs text-accent-ink underline" onclick={() => show(false)}
				>{m.plan_help_hide()}</button
			>
		</div>
		<ul class="flex flex-col gap-1.5">
			<li class="flex items-center gap-2">
				<span class="anchor anchor-start shrink-0" style="cursor: default"></span>
				{m.plan_point_start()}
			</li>
			<li class="flex items-center gap-2">
				<span class="anchor shrink-0" style="cursor: default">1</span>
				{m.plan_help_via()}
			</li>
			<li class="flex items-center gap-2">
				<span class="anchor anchor-end shrink-0" style="cursor: default"></span>
				{m.plan_point_end()}
			</li>
			<li class="flex items-center gap-2">
				<span class="midpoint shrink-0" style="cursor: default"></span>
				{m.plan_midpoint_title()}
			</li>
		</ul>
		<ul class="mt-2 list-disc pl-4 text-stone-600">
			<li>{m.plan_help_click()}</li>
			<li>{m.plan_help_drag()}</li>
			<li>{m.plan_help_round()}</li>
		</ul>
	</section>
{:else if open === false}
	<button
		type="button"
		class="self-start text-sm text-accent-ink underline"
		data-testid="plan-help-open"
		onclick={() => show(true)}>{m.plan_help_title()}</button
	>
{/if}
