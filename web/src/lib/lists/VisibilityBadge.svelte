<script lang="ts">
	import Globe from '@lucide/svelte/icons/globe';
	import Link from '@lucide/svelte/icons/link';
	import Lock from '@lucide/svelte/icons/lock';
	import Users from '@lucide/svelte/icons/users';
	import { m } from '#lib/paraglide/messages.js';

	// Who can see a route, journey or collection, at a glance (feedback issue
	// 45); with role, one shared with the viewer.
	let {
		visibility,
		role,
		owner
	}: {
		visibility?: 'private' | 'unlisted' | 'public';
		role?: 'viewer' | 'editor';
		owner?: string;
	} = $props();

	const [Icon, label, hint] = $derived(
		role
			? [
					Users,
					role === 'editor' ? m.role_editor() : m.role_viewer(),
					m.shared_by({ user: owner ?? '' })
				]
			: visibility === 'public'
				? [Globe, m.visibility_public(), m.visibility_public_hint()]
				: visibility === 'unlisted'
					? [Link, m.visibility_by_link(), m.visibility_unlisted_hint()]
					: [Lock, m.visibility_private(), m.visibility_private_hint()]
	);
</script>

<span
	class="relative inline-flex items-center gap-1 rounded-full bg-stone-100 px-2 py-0.5 text-xs whitespace-nowrap text-stone-600"
	title={hint}
	data-testid="visibility"
	><Icon class="size-3.5" aria-hidden="true" />{label}<span class="sr-only">: {hint}</span></span
>
