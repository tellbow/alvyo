<script lang="ts">
	import MessageCircle from '@lucide/svelte/icons/message-circle';
	import { actionButton } from '#lib/components/actions.js';
	import { m } from '#lib/paraglide/messages.js';
	import type { Community } from './community.svelte';

	// The comments' count at the top of a page; a click opens their tab.
	let { community, onclick }: { community: Community; onclick: () => void } = $props();
	const n = $derived(community.social?.comments.length ?? 0);
</script>

{#if community.social}
	<button
		type="button"
		class={actionButton}
		aria-label={m.community_comments({ n })}
		title={m.community_comments({ n })}
		{onclick}
		data-testid="comments-count"
		><MessageCircle class="inline size-4 align-[-3px]" aria-hidden="true" /> {n}</button
	>
{/if}
