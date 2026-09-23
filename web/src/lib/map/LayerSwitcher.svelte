<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import { baseLabel, overlayLabel } from './labels';
	import { BASE_MAPS, OVERLAYS, type BaseMapId, type OverlayId } from './styles';

	let {
		base = $bindable<BaseMapId>(),
		overlays = $bindable<OverlayId[]>()
	}: { base: BaseMapId; overlays: OverlayId[] } = $props();
	let open = $state(false);
</script>

<div class="absolute top-2 left-2 z-10 text-sm">
	<button
		type="button"
		class="rounded-md bg-white px-3 py-1.5 shadow ring-1 ring-stone-300 hover:bg-stone-50"
		aria-expanded={open}
		onclick={() => (open = !open)}
	>
		{m.map_layers()}
	</button>
	{#if open}
		<div class="mt-2 w-64 rounded-md bg-white p-3 shadow ring-1 ring-stone-300">
			<fieldset>
				<legend class="mb-1 font-medium">{m.map_base()}</legend>
				{#each BASE_MAPS as id (id)}
					<label class="flex items-center gap-2 py-0.5">
						<input type="radio" name="base" value={id} bind:group={base} />
						{baseLabel[id]()}
					</label>
				{/each}
			</fieldset>
			<fieldset class="mt-3">
				<legend class="mb-1 font-medium">{m.map_overlays()}</legend>
				{#each OVERLAYS as id (id)}
					<label class="flex items-center gap-2 py-0.5">
						<input type="checkbox" value={id} bind:group={overlays} />
						{overlayLabel[id]()}
					</label>
				{/each}
			</fieldset>
		</div>
	{/if}
</div>
