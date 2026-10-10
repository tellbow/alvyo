<script lang="ts">
	import { m } from '#lib/paraglide/messages.js';
	import type { Map as MapLibreMap, Marker } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import type { Gallery } from './gallery.svelte';

	let { map, lib, gallery }: { map: MapLibreMap; lib: typeof MapLibre; gallery: Gallery } =
		$props();

	// One marker with the thumbnail for every photo taken along the route.
	$effect(() => {
		const markers: Marker[] = [];
		for (const p of gallery.photos) {
			if (!p.pin) continue;
			const el = document.createElement('button');
			el.type = 'button';
			el.className =
				'block size-9 overflow-hidden rounded-full border-2 border-white shadow-md bg-stone-200';
			el.setAttribute('aria-label', p.caption || m.photos_open());
			el.dataset.testid = 'photo-pin';
			const img = document.createElement('img');
			img.src = gallery.src(p, 'thumb');
			img.alt = '';
			img.className = 'h-full w-full object-cover';
			el.append(img);
			el.addEventListener('click', (e) => {
				e.stopPropagation();
				gallery.open = p.id;
			});
			markers.push(
				new lib.Marker({ element: el })
					.setLngLat([p.pin[0], p.pin[1]] as [number, number])
					.addTo(map)
			);
		}
		return () => markers.forEach((mk) => mk.remove());
	});
</script>
