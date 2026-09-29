<script lang="ts">
	import { m } from '$lib/paraglide/messages';
	import { baseLabel, overlayLabel } from './labels';
	import PoiIcon from './PoiIcon.svelte';
	import { POI_KINDS, poiLabel } from './places';
	import { poiShown, togglePoiKind } from './poiKinds.svelte';
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
		class="rounded-md bg-surface px-3 py-1.5 shadow ring-1 ring-stone-300 hover:bg-stone-50"
		aria-expanded={open}
		onclick={() => (open = !open)}
	>
		{m.map_layers()}
	</button>
	{#if open}
		<div
			class="mt-2 max-h-[70dvh] w-64 overflow-y-auto rounded-md bg-surface p-3 shadow ring-1 ring-stone-300"
		>
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
					{#if id === 'pois' && overlays.includes('pois')}
						<fieldset class="ml-6 grid grid-cols-1 gap-x-2" data-testid="poi-kinds">
							<legend class="sr-only">{m.map_poi_kinds()}</legend>
							{#each POI_KINDS as kind (kind)}
								<label class="flex items-center gap-2 py-0.5">
									<input
										type="checkbox"
										checked={poiShown.kinds.includes(kind)}
										onchange={() => togglePoiKind(kind)}
									/>
									<PoiIcon {kind} />
									{poiLabel(kind)}
								</label>
							{/each}
						</fieldset>
					{/if}
				{/each}
			</fieldset>
		</div>
	{/if}
</div>
