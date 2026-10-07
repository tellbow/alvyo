<script lang="ts">
	import { untrack } from 'svelte';
	import type { ImageSource, Map as MapLibreMap } from 'maplibre-gl';
	import { api, type Precip } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { intlLocale } from '$lib/util/locale';
	import { OVERLAY_PREFIX, ROUTE_PREFIX } from './styles';

	let { map }: { map: MapLibreMap } = $props();

	const ID = OVERLAY_PREFIX + 'precip';
	// Rain goes below the places and the routes.
	const ABOVE = ['huts', 'lodging', 'pois'].map((id) => OVERLAY_PREFIX + id);

	let timeline = $state<Precip>();
	let index = $state(0);
	let playing = $state(false);
	const frame = $derived(timeline?.frames[index]);

	// The timeline every 5 minutes; it starts at the newest radar picture
	// and keeps the time shown when it can.
	$effect(() => {
		let stopped = false;
		async function load() {
			const { data } = await api().GET('/weather/precip');
			if (stopped || !data) return;
			const shown = untrack(() => frame?.time);
			timeline = data;
			const same = data.frames.findIndex((f) => f.time === shown);
			index =
				same >= 0
					? same
					: Math.max(
							data.frames.findLastIndex((f) => f.kind === 'radar'),
							0
						);
			for (const f of data.frames) new Image().src = f.url; // switching without waiting
		}
		load();
		const timer = setInterval(load, 5 * 60_000);
		return () => {
			stopped = true;
			clearInterval(timer);
		};
	});

	$effect(() => {
		if (!playing || !timeline) return;
		const n = timeline.frames.length;
		const timer = setInterval(() => (index = (index + 1) % n), 700);
		return () => clearInterval(timer);
	});

	$effect(() => {
		const f = frame;
		const b = timeline?.bounds;
		if (!f || !b) return;
		const coordinates: [[number, number], [number, number], [number, number], [number, number]] = [
			[b.west, b.north],
			[b.east, b.north],
			[b.east, b.south],
			[b.west, b.south]
		];
		const show = () => {
			const source = map.getSource(ID) as ImageSource | undefined;
			if (source) {
				source.updateImage({ url: f.url, coordinates });
				return;
			}
			map.addSource(ID, { type: 'image', url: f.url, coordinates });
			const below = map
				.getStyle()
				.layers.find((l) => l.id.startsWith(ROUTE_PREFIX) || ABOVE.includes(l.id))?.id;
			map.addLayer(
				{
					id: ID,
					type: 'raster',
					source: ID,
					paint: { 'raster-opacity': 0.8, 'raster-fade-duration': 0 }
				},
				below
			);
		};
		try {
			show();
		} catch {
			map.once('style.load', show); // a new base map is loading
		}
	});

	$effect(() => () => {
		try {
			if (map.getLayer(ID)) map.removeLayer(ID);
			if (map.getSource(ID)) map.removeSource(ID);
		} catch {
			// the map is gone
		}
	});

	const zurich = (d: Date, o: Intl.DateTimeFormatOptions) =>
		new Intl.DateTimeFormat(intlLocale(), { timeZone: 'Europe/Zurich', ...o }).format(d);

	/** «09:45», a forecast hour «09:00–10:00»; with the weekday when not today. */
	function label(f: { kind: string; time: string }) {
		const end = new Date(f.time);
		const hm = { hour: '2-digit', minute: '2-digit' } as const;
		const day =
			zurich(end, { dateStyle: 'short' }) === zurich(new Date(), { dateStyle: 'short' })
				? ''
				: zurich(end, { weekday: 'short' }) + ' ';
		if (f.kind === 'radar') return day + zurich(end, hm);
		return `${day}${zurich(new Date(end.getTime() - 3_600_000), hm)}–${zurich(end, hm)}`;
	}
</script>

<div
	class="absolute top-12 left-2 z-10 w-72 max-w-[calc(100%-4.5rem)] rounded-md bg-surface/95 p-2 text-xs shadow ring-1 ring-stone-300"
	data-testid="precip"
>
	{#if timeline && timeline.frames.length === 0}
		<p>{m.precip_none()}</p>
	{:else if timeline && frame}
		<div class="flex items-center gap-2">
			<button
				type="button"
				class="w-6 rounded px-1 text-sm hover:bg-stone-100"
				aria-label={playing ? m.precip_pause() : m.precip_play()}
				onclick={() => (playing = !playing)}>{playing ? '❚❚' : '▶'}</button
			>
			<input
				type="range"
				class="flex-1"
				min="0"
				max={timeline.frames.length - 1}
				aria-label={m.precip_time()}
				bind:value={index}
				oninput={() => (playing = false)}
			/>
		</div>
		<div class="mt-1 flex justify-between gap-2">
			<span class="font-medium tabular-nums" data-testid="precip-time">{label(frame)}</span>
			<span class="text-stone-600" data-testid="precip-kind"
				>{frame.kind === 'radar' ? m.precip_radar() : m.precip_forecast()}</span
			>
		</div>
		<div class="mt-1.5 flex h-2 overflow-hidden rounded-sm" aria-hidden="true">
			{#each timeline.legend as l (l.from)}
				<span class="flex-1" style:background={l.color}></span>
			{/each}
		</div>
		<div class="flex justify-between text-stone-500">
			<span>{m.precip_light()}</span>
			<span>© {timeline.attribution}</span>
			<span>{m.precip_heavy()}</span>
		</div>
	{/if}
</div>
