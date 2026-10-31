<script lang="ts">
	import UserRound from '@lucide/svelte/icons/user-round';

	/** A person's round profile picture, or a portrait icon without one. */
	let { id, class: size = 'size-10' }: { id?: string; class?: string } = $props();
</script>

{#if id}
	<img
		src="/api/v1/avatars/{id}"
		alt=""
		class="{size} shrink-0 rounded-full bg-accent-soft object-cover"
		loading="lazy"
	/>
{:else}
	<span
		class="{size} flex shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent-ink"
		aria-hidden="true"
	>
		<UserRound class="size-3/5" />
	</span>
{/if}
