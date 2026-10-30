<script lang="ts">
	// The trail marking: the yellow diamond of a Wanderweg, white-red-white
	// of a Bergwanderweg, white-blue-white of an Alpinwanderweg (feedback
	// issue 71). Its name stands beside it, so screen readers skip it.
	let { trail }: { trail: string } = $props();
</script>

{#if trail === 'Wanderweg'}
	<svg viewBox="0 0 16 16" class="size-3 shrink-0" aria-hidden="true">
		<path d="M8 1 15 8 8 15 1 8Z" fill="#fcd116" stroke="#1a1a1a" stroke-width="1.5" />
	</svg>
{:else if trail === 'Bergwanderweg' || trail === 'Alpinwanderweg'}
	<svg viewBox="0 0 18 12" class="h-2.5 w-[15px] shrink-0" aria-hidden="true">
		<rect width="18" height="12" fill="#fff" stroke="#1a1a1a" stroke-width="1" />
		<rect y="4" width="18" height="4" fill={trail === 'Bergwanderweg' ? '#e3242b' : '#2f6fde'} />
	</svg>
{/if}
