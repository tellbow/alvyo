<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '#lib/api/client.js';

	// One's friends offered while typing a username (<input list={id}>).
	let { id }: { id: string } = $props();

	let friends = $state<{ username: string; display_name: string }[]>([]);
	onMount(async () => {
		const { data } = await api().GET('/me/friends');
		friends = data?.friends ?? [];
	});
</script>

<datalist {id}>
	{#each friends as f (f.username)}
		<option value={f.username}>{f.display_name}</option>
	{/each}
</datalist>
