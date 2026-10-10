<script lang="ts">
	import type { Me } from '#lib/api/client.js';
	import { actionButton } from '#lib/components/actions.js';
	import { m } from '#lib/paraglide/messages.js';
	import type { Community } from './community.svelte';

	// «Merken» at the top of a page: the same like as the one with the comments.
	let { community, user, testid }: { community: Community; user: Me | null; testid: string } =
		$props();
</script>

<button
	type="button"
	class="{actionButton} {community.social?.liked ? 'text-rose-700 dark:text-rose-400' : ''}"
	aria-pressed={community.social?.liked ?? false}
	disabled={!user || !community.social || community.busy}
	title={user ? undefined : m.community_login_to_like()}
	onclick={() => community.like()}
	data-testid={testid}>{community.social?.liked ? '♥' : '♡'} {m.route_like()}</button
>
