<script lang="ts">
	import type { ExpressionSpecification, Map as MapLibreMap } from 'maplibre-gl';
	import { ROUTE_PREFIX } from '#lib/map/styles.js';
	import { ROUTE_COLOR } from './colors';

	/** Draws the route's line from start to end once, over RouteLayers' line, which shows after. */
	let { map, line }: { map: MapLibreMap; line: number[][] } = $props();

	const DRAW = `${ROUTE_PREFIX}draw`;
	const HIDDEN = ['casing', 'line', 'line-straight'].map((l) => `${ROUTE_PREFIX}${l}`);
	const MS = 1200;

	/** The line up to `p` (0–1) in `color`, the rest not drawn. */
	const upTo = (color: string, p: number): ExpressionSpecification => [
		'step',
		['line-progress'],
		color,
		Math.max(p, 1e-6),
		'rgba(0,0,0,0)'
	];

	$effect(() => {
		if (line.length < 2 || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
		// lineMetrics: line-progress (0 at the start, 1 at the end) for line-gradient.
		map.addSource(DRAW, {
			type: 'geojson',
			lineMetrics: true,
			data: { type: 'LineString', coordinates: line }
		});
		const layer = (id: string, color: string, width: number) =>
			map.addLayer({
				id,
				type: 'line',
				source: DRAW,
				layout: { 'line-join': 'round', 'line-cap': 'round' },
				paint: { 'line-width': width, 'line-gradient': upTo(color, 0) }
			});
		layer(`${DRAW}-casing`, '#ffffff', 8);
		layer(DRAW, ROUTE_COLOR, 4.5);
		for (const id of HIDDEN) if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', 'none');

		const start = performance.now();
		let frame = requestAnimationFrame(function step(now) {
			if (!map.getLayer(DRAW)) return; // a base map switch removed it
			const t = Math.min((now - start) / MS, 1);
			const p = 1 - (1 - t) ** 3; // ease out
			for (const [id, color] of [
				[`${DRAW}-casing`, '#ffffff'],
				[DRAW, ROUTE_COLOR]
			])
				map.setPaintProperty(id, 'line-gradient', upTo(color, p));
			if (t < 1) frame = requestAnimationFrame(step);
			else done();
		});
		function done() {
			cancelAnimationFrame(frame);
			for (const id of HIDDEN)
				if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', 'visible');
			for (const id of [DRAW, `${DRAW}-casing`]) if (map.getLayer(id)) map.removeLayer(id);
			if (map.getSource(DRAW)) map.removeSource(DRAW);
		}
		return done;
	});
</script>
