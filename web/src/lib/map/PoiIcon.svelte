<script lang="ts">
	import type { PoiKind } from './places';
	import { POI_ICONS } from './poiIcons';

	let { kind, size = 18 }: { kind: PoiKind; size?: number } = $props();
	const icon = $derived(POI_ICONS[kind]);
</script>

<svg
	width={size}
	height={size}
	viewBox="0 0 24 24"
	aria-hidden="true"
	class="shrink-0 print:size-3"
>
	<circle cx="12" cy="12" r="12" fill={icon.color} />
	<path
		transform="translate(3.6 3.6) scale(0.7)"
		fill="#fff"
		fill-rule={icon.evenodd ? 'evenodd' : 'nonzero'}
		d={icon.path}
	/>
</svg>
