<script lang="ts">
	import { api } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';

	type Friend = 'none' | 'requested' | 'incoming' | 'friends';
	// Asking, accepting, declining and ending a friendship with a user.
	let {
		username,
		friend: initial,
		onchange
	}: { username: string; friend: Friend; onchange?: (friend: Friend) => void } = $props();

	// svelte-ignore state_referenced_locally
	let friend = $state(initial);

	const hydrated = new Hydrated();
	let busy = $state(false);

	async function set(on: boolean) {
		busy = true;
		const params = { params: { path: { username } } };
		const { data } = on
			? await api().PUT('/users/{username}/friend', params)
			: await api().DELETE('/users/{username}/friend', params);
		busy = false;
		if (data) {
			friend = data.friend;
			onchange?.(friend);
		}
	}

	const primary =
		'rounded-md bg-accent px-3 py-1.5 text-on-accent hover:bg-accent-hover disabled:opacity-60';
	const quiet = 'text-stone-500 underline disabled:opacity-60';
	const disabled = $derived(busy || !hydrated.value);
</script>

<span class="flex flex-wrap items-center gap-3 text-sm" data-testid="friend" data-friend={friend}>
	{#if friend === 'none'}
		<button type="button" class={primary} {disabled} onclick={() => set(true)}
			>{m.friend_add()}</button
		>
	{:else if friend === 'requested'}
		<span class="text-stone-600">{m.friend_requested()}</span>
		<button type="button" class={quiet} {disabled} onclick={() => set(false)}
			>{m.friend_withdraw()}</button
		>
	{:else if friend === 'incoming'}
		<button type="button" class={primary} {disabled} onclick={() => set(true)}
			>{m.friend_accept()}</button
		>
		<button type="button" class={quiet} {disabled} onclick={() => set(false)}
			>{m.friend_decline()}</button
		>
	{:else}
		<span class="text-stone-600">✓ {m.friend_friends()}</span>
		<button type="button" class={quiet} {disabled} onclick={() => set(false)}
			>{m.friend_remove()}</button
		>
	{/if}
</span>
