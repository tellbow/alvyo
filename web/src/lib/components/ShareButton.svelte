<script lang="ts">
	import { page } from '$app/state';
	import { m } from '#lib/paraglide/messages.js';
	import { actionButton } from './actions';

	// The page's address to send, with the share token if there is one: the
	// phone's share sheet, else copied.
	let { title, token, testid }: { title: string; token?: string; testid: string } = $props();

	let copied = $state(false);

	async function share() {
		const url = `${page.url.origin}${page.url.pathname}${token ? `?t=${encodeURIComponent(token)}` : ''}`;
		if (navigator.share) {
			await navigator.share({ title, url }).catch(() => {});
			return;
		}
		await navigator.clipboard.writeText(url);
		copied = true;
		setTimeout(() => (copied = false), 2000);
	}
</script>

<button
	type="button"
	class={actionButton}
	aria-label={copied ? m.share_copied() : m.route_share()}
	title={copied ? m.share_copied() : m.route_share()}
	onclick={share}
	data-testid={testid}
>
	{#if copied}{m.share_copied()}{:else}
		<svg
			width="16"
			height="16"
			viewBox="0 0 24 24"
			fill="none"
			stroke="currentColor"
			stroke-width="2"
			stroke-linecap="round"
			stroke-linejoin="round"
			aria-hidden="true"
			><path d="M12 15V3M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" /></svg
		>
	{/if}
</button>
<span class="sr-only" aria-live="polite">{copied ? m.share_copied() : ''}</span>
