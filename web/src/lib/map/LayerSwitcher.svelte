<script lang="ts">
	import { m } from '#lib/paraglide/messages.js';
	import { baseLabel, overlayLabel } from './labels';
	import PoiIcon from './PoiIcon.svelte';
	import { POI_KINDS, poiLabel } from './places';
	import { poiShown, togglePoiKind } from './poiKinds.svelte';
	import { BASE_MAPS, OVERLAYS, type BaseMapId, type OverlayId } from './styles';

	let {
		base = $bindable<BaseMapId>(),
		overlays = $bindable<OverlayId[]>()
	}: { base: BaseMapId; overlays: OverlayId[] } = $props();
	const uid = $props.id();
	let open = $state(false);
	let box = $state<HTMLElement>();
	let trigger = $state<HTMLButtonElement>();
</script>

<!-- Closes on a click beside it or Escape, as MoreMenu. -->
<svelte:window
	onclick={(e) => {
		if (open && box && !e.composedPath().includes(box)) open = false;
	}}
	onkeydown={(e) => {
		if (e.key === 'Escape' && open) {
			open = false;
			trigger?.focus();
		}
	}}
/>

<div class="absolute top-2 left-2 z-10 text-sm" bind:this={box}>
	<button
		bind:this={trigger}
		type="button"
		class="rounded-md bg-surface px-3 py-1.5 shadow ring-1 ring-stone-300 hover:bg-stone-50"
		aria-expanded={open}
		aria-controls="{uid}-layers"
		onclick={() => (open = !open)}
	>
		{m.map_layers()}
	</button>
	{#if open}
		<div
			id="{uid}-layers"
			class="mt-2 max-h-[70dvh] w-64 overflow-y-auto rounded-md bg-surface p-3 shadow ring-1 ring-stone-300"
		>
			<fieldset>
				<legend class="mb-1 font-medium">{m.map_base()}</legend>
				{#each BASE_MAPS as id (id)}
					<label class="flex items-center gap-2 py-0.5 pointer-coarse:py-2">
						<input type="radio" name="base" value={id} bind:group={base} />
						{baseLabel[id]()}
					</label>
				{/each}
			</fieldset>
			<fieldset class="mt-3">
				<legend class="mb-1 font-medium">{m.map_overlays()}</legend>
				{#each OVERLAYS as id (id)}
					<label class="flex items-center gap-2 py-0.5 pointer-coarse:py-2">
						<input type="checkbox" value={id} bind:group={overlays} />
						{overlayLabel[id]()}
					</label>
					{#if id === 'pois' && overlays.includes('pois')}
						<fieldset class="ml-6 grid grid-cols-1 gap-x-2" data-testid="poi-kinds">
							<legend class="sr-only">{m.map_poi_kinds()}</legend>
							{#each POI_KINDS as kind (kind)}
								<label class="flex items-center gap-2 py-0.5 pointer-coarse:py-2">
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
