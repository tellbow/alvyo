<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { adminApi } from '#lib/api/client.js';
	import { refused } from './admin';

	/** The last action: what it did and its entry in «Verlauf», to undo it
	 * right here. */
	let { done = $bindable() }: { done?: { text: string; logId?: string } } = $props();
	let error = $state('');

	async function undo() {
		if (!done?.logId) return;
		const { response } = await adminApi().POST('/admin/log/{id}/undo', {
			params: { path: { id: done.logId } }
		});
		if (response.ok) {
			done = { text: 'Rückgängig gemacht.' };
			await invalidateAll();
		} else {
			error = refused(response.status);
		}
	}
</script>

{#if done}
	<div
		role="status"
		class="mb-4 flex flex-wrap items-center gap-3 rounded-lg bg-stone-900 px-4 py-2 text-sm text-white"
		data-testid="admin-done"
	>
		<span class="flex-1">{done.text}</span>
		{#if done.logId}
			<button type="button" class="font-semibold underline" onclick={undo}>Rückgängig</button>
		{/if}
		<button type="button" aria-label="Schliessen" onclick={() => (done = undefined)}>✕</button>
	</div>
{/if}
{#if error}<p role="alert" class="mb-4 text-sm text-red-700 dark:text-red-400">{error}</p>{/if}
