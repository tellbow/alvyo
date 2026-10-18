<script lang="ts">
	import { ROUTE_COLOR } from './colors';
	import type { FilterSpecification, GeoJSONSource, Map as MapLibreMap, Marker } from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { api } from '#lib/api/client.js';
	import { OSM_ATTRIBUTION, ROUTE_PREFIX } from '#lib/map/styles.js';
	import { m } from '#lib/paraglide/messages.js';
	import { distinctPoint, nearestWay, otherWays, type Way } from './dragWays';
	import { legFeatures } from './geojson';
	import type { Planner } from './planner.svelte';

	let {
		map,
		lib,
		planner,
		hover,
		editable = true,
		ghosts = []
	}: {
		map: MapLibreMap;
		lib: typeof MapLibre;
		planner: Planner;
		/** position to highlight (from the elevation profile) */
		hover?: [number, number];
		/** anchors can be dragged and removed */
		editable?: boolean;
		/** reference points, e.g. the ends of neighbouring journey stages */
		ghosts?: { at: number[]; label: string }[];
	} = $props();

	const LEGS = `${ROUTE_PREFIX}legs`;
	const HOVER = `${ROUTE_PREFIX}hover`;
	/** Dashed lines to the neighbouring points while a point or a leg's dot is dragged. */
	const DRAG = `${ROUTE_PREFIX}drag`;
	/** The other ways of a leg while its dot is dragged. */
	const WAYS = `${ROUTE_PREFIX}ways`;
	/** How close to another way a leg's dot is let go to take it, in pixels. */
	const REACH_PX = 40;
	const COLOR = ROUTE_COLOR;

	const empty = { type: 'FeatureCollection' as const, features: [] };

	function addLayers() {
		if (map.getSource(LEGS)) return; // carried over from the previous base map
		map.addSource(LEGS, {
			type: 'geojson',
			data: empty,
			attribution: OSM_ATTRIBUTION
		});
		map.addSource(HOVER, { type: 'geojson', data: empty });
		map.addSource(DRAG, { type: 'geojson', data: empty });
		map.addSource(WAYS, { type: 'geojson', data: empty });
		const ok: FilterSpecification = ['==', ['get', 'state'], 'ok'];
		// Below the route: the ways it can be dragged onto, the one in reach stronger.
		map.addLayer({
			id: WAYS,
			type: 'line',
			source: WAYS,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: {
				'line-color': '#0e7490',
				'line-width': ['case', ['get', 'near'], 8, 5],
				'line-opacity': ['case', ['get', 'near'], 0.9, 0.45]
			}
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}casing`,
			type: 'line',
			source: LEGS,
			filter: ok,
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': '#ffffff', 'line-width': 8, 'line-opacity': 0.85 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}line`,
			type: 'line',
			source: LEGS,
			filter: ['all', ok, ['!', ['get', 'straight']]],
			layout: { 'line-join': 'round', 'line-cap': 'round' },
			paint: { 'line-color': COLOR, 'line-width': 4.5 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}line-straight`,
			type: 'line',
			source: LEGS,
			filter: ['all', ok, ['get', 'straight']],
			paint: { 'line-color': COLOR, 'line-width': 4, 'line-dasharray': [2, 1.5] }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}pending`,
			type: 'line',
			source: LEGS,
			filter: ['!=', ['get', 'state'], 'ok'],
			paint: {
				'line-color': ['match', ['get', 'state'], 'error', '#dc2626', '#5d6a62'],
				'line-width': 3,
				'line-dasharray': [1, 1.5]
			}
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}drag`,
			type: 'line',
			source: DRAG,
			paint: { 'line-color': COLOR, 'line-width': 3, 'line-dasharray': [2, 2], 'line-opacity': 0.8 }
		});
		map.addLayer({
			id: `${ROUTE_PREFIX}hover`,
			type: 'circle',
			source: HOVER,
			paint: {
				'circle-radius': 6,
				'circle-color': COLOR,
				'circle-stroke-color': '#ffffff',
				'circle-stroke-width': 2
			}
		});
	}

	/** Shows dashed lines from the neighbouring points to `at`; without `at`, hides them. */
	function band(at?: [number, number], before?: number, after?: number) {
		const line = [before, after].flatMap((i) =>
			i !== undefined && i >= 0 && i < planner.anchors.length ? [snapped(i)] : []
		);
		if (at) line.splice(before !== undefined && before >= 0 ? 1 : 0, 0, at);
		(map.getSource(DRAG) as GeoJSONSource | undefined)?.setData(
			at && line.length > 1 ? { type: 'LineString', coordinates: line } : empty
		);
	}

	type Ways = { all: Way[]; others: { way: Way; index: number }[] };

	/** The ways between the ends of leg `i`; undefined when they cannot be had. */
	async function waysOf(i: number): Promise<Ways | undefined> {
		const from = planner.anchors[i];
		const to = planner.anchors[i + 1];
		if (!from || !to) return { all: [], others: [] };
		const { data } = await api().POST('/routing/alternatives', {
			body: {
				from: { lon: from.lon, lat: from.lat },
				to: { lon: to.lon, lat: to.lat },
				profile: to.alpine ? 'alpine' : planner.profile
			}
		});
		if (!data) return undefined;
		const all = data.ways as Way[];
		const slot = planner.legs[i];
		return { all, others: otherWays(all, slot?.state === 'ok' ? slot.leg.coordinates : []) };
	}

	/** Shows the other ways, `near` (an index among all) stronger; without ways, hides them. */
	function showWays(ways: { way: Way; index: number }[] = [], near?: number) {
		(map.getSource(WAYS) as GeoJSONSource | undefined)?.setData({
			type: 'FeatureCollection',
			features: ways.map((w) => ({
				type: 'Feature',
				properties: { near: w.index === near },
				geometry: { type: 'LineString', coordinates: w.way }
			}))
		});
	}

	function renderLegs() {
		(map.getSource(LEGS) as GeoJSONSource | undefined)?.setData(
			legFeatures(planner.anchors, planner.legs)
		);
	}

	function renderHover() {
		(map.getSource(HOVER) as GeoJSONSource | undefined)?.setData(
			hover ? { type: 'Point', coordinates: hover } : empty
		);
	}

	$effect(() => {
		addLayers();
		// After a base map switch the sources exist again but data must be reapplied.
		const onStyle = () => {
			addLayers();
			renderLegs();
			renderHover();
		};
		map.on('style.load', onStyle);
		return () => map.off('style.load', onStyle);
	});

	$effect(() => {
		// Track the reactive inputs, then draw.
		void [planner.anchors.map((a) => [a.lon, a.lat, a.straight, a.through]), planner.legs];
		renderLegs();
	});

	// Apart from the line: the hover moves with every pointer move over the
	// profile, and the whole line need not be sent to the map for that.
	$effect(() => {
		void hover;
		renderHover();
	});

	// Draggable numbered markers, reconciled by anchor id. Deliberately not
	// reactive: the effect below writes it and must not re-run because of it.
	// eslint-disable-next-line svelte/prefer-svelte-reactivity
	const markers = new Map<number, Marker>();

	/** Where anchor i sits on the computed route (it snaps to the path). */
	function snapped(i: number): [number, number] {
		const before = planner.legs[i - 1];
		const after = planner.legs[i];
		const c =
			before?.state === 'ok'
				? before.leg.coordinates.at(-1)
				: after?.state === 'ok'
					? after.leg.coordinates[0]
					: undefined;
		const a = planner.anchors[i];
		return c ? [c[0], c[1]] : [a.lon, a.lat];
	}

	$effect(() => {
		const anchors = planner.anchors;
		void planner.legs; // re-snap when legs arrive
		// eslint-disable-next-line svelte/prefer-svelte-reactivity -- local to this run
		const seen = new Set<number>();
		anchors.forEach((a, i) => {
			seen.add(a.id);
			let marker = markers.get(a.id);
			if (!marker) {
				// MapLibre owns the outer element's classes (positioning); our
				// styling lives on an inner element.
				const el = document.createElement('div');
				el.appendChild(document.createElement('div'));
				marker = new lib.Marker({ element: el, draggable: editable })
					.setLngLat([a.lon, a.lat])
					.addTo(map);
				const id = a.id;
				marker.on('drag', () => {
					const p = markers.get(id)!.getLngLat();
					const i = planner.anchors.findIndex((x) => x.id === id);
					band([p.lng, p.lat], i - 1, i + 1);
				});
				marker.on('dragend', () => {
					const p = markers.get(id)!.getLngLat();
					band();
					planner.move(id, p.lng, p.lat);
				});
				el.addEventListener('dblclick', (e) => {
					e.stopPropagation();
					if (editable) planner.remove(id);
				});
				markers.set(a.id, marker);
			}
			marker.setLngLat(snapped(i));
			const dot = marker.getElement().firstElementChild as HTMLElement;
			const kind = i === 0 ? 'start' : i === anchors.length - 1 ? 'end' : 'via';
			dot.className = `anchor anchor-${kind}`;
			dot.textContent = kind === 'via' ? String(i) : '';
			dot.dataset.testid = 'anchor';
		});
		for (const [id, marker] of markers) {
			if (!seen.has(id)) {
				marker.remove();
				markers.delete(id);
			}
		}
	});

	$effect(() => () => {
		for (const marker of markers.values()) marker.remove();
		markers.clear();
	});

	/**
	 * A leg's dot let go at `at`: on another way within reach the leg takes
	 * it (the shortest one: no shape); elsewhere, or without other ways, a
	 * stop goes there. As in the app (feedback issue 3).
	 */
	async function dropLeg(leg: number, at: [number, number], ways: Promise<Ways | undefined>) {
		const [from, to] = [planner.anchors[leg], planner.anchors[leg + 1]];
		const w = await ways;
		showWays();
		// Points added, moved or undone meanwhile: the leg is another.
		if (planner.anchors[leg] !== from || planner.anchors[leg + 1] !== to) return;
		const near = w && nearestWay(w.others, map.project(at), (p) => map.project(p));
		if (!near || near.px > REACH_PX) return planner.insert(leg + 1, at[0], at[1]);
		if (near.way.index === 0) planner.unshape(leg);
		else {
			const p = distinctPoint(
				near.way.way,
				w!.all.filter((_, i) => i !== near.way.index)
			);
			planner.reroute(leg, p[0], p[1]);
		}
	}

	// A dot halfway along each computed leg: dragged, the other ways between
	// its points show (a straight leg has none), and the dashed lines to them.
	$effect(() => {
		if (!editable) return;
		const anchors = planner.anchors;
		const placed = planner.legs.flatMap((slot, leg) => {
			if (slot?.state !== 'ok' || leg + 1 >= anchors.length) return [];
			const line = slot.leg.coordinates;
			const mid = line[Math.floor(line.length / 2)];
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			const dot = el.firstElementChild as HTMLElement;
			dot.className = 'midpoint';
			dot.title = m.plan_midpoint_title();
			dot.dataset.testid = 'midpoint';
			const marker = new lib.Marker({ element: el, draggable: true })
				.setLngLat([mid[0], mid[1]])
				.addTo(map);
			const straight = !!anchors[leg + 1]?.straight;
			let ways: Promise<Ways | undefined> = Promise.resolve(undefined);
			let got: Ways | undefined;
			const at = (): [number, number] => {
				const p = marker.getLngLat();
				return [p.lng, p.lat];
			};
			marker.on('dragstart', () => {
				got = undefined;
				if (!straight) ways = waysOf(leg).then((w) => (got = w));
			});
			marker.on('drag', () => {
				band(at(), leg, leg + 1);
				const near = got && nearestWay(got.others, map.project(at()), (p) => map.project(p));
				showWays(got?.others, near && near.px <= REACH_PX ? near.way.index : undefined);
			});
			marker.on('dragend', () => {
				band();
				void dropLeg(leg, at(), ways);
			});
			return [marker];
		});
		return () => placed.forEach((mk) => mk.remove());
	});

	/** Where leg i passes closest to p: the dot of a leg dragged onto a path. */
	function onLeg(i: number, p: { lon: number; lat: number }): [number, number] {
		const slot = planner.legs[i];
		if (slot?.state !== 'ok') return [p.lon, p.lat];
		const k = Math.cos((p.lat * Math.PI) / 180);
		let best: [number, number] = [p.lon, p.lat];
		let bestD = Infinity;
		for (const c of slot.leg.coordinates) {
			const d = ((c[0] - p.lon) * k) ** 2 + (c[1] - p.lat) ** 2;
			if (d < bestD) [best, bestD] = [[c[0], c[1]], d];
		}
		return best;
	}

	$effect(() => {
		const placed = planner.anchors.flatMap((a, i) => {
			if (!a.through || a.straight) return [];
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			const dot = el.firstElementChild as HTMLElement;
			dot.className = 'through';
			dot.title = editable ? m.plan_through_title() : '';
			dot.dataset.testid = 'through';
			el.addEventListener('dblclick', (e) => {
				e.stopPropagation();
				if (editable) planner.unshape(i - 1);
			});
			return [new lib.Marker({ element: el }).setLngLat(onLeg(i - 1, a.through)).addTo(map)];
		});
		return () => placed.forEach((mk) => mk.remove());
	});

	$effect(() => {
		const placed = ghosts.map((g) => {
			const el = document.createElement('div');
			el.appendChild(document.createElement('div'));
			const dot = el.firstElementChild as HTMLElement;
			dot.className = 'ghost';
			dot.title = g.label;
			dot.dataset.testid = 'ghost';
			return new lib.Marker({ element: el }).setLngLat(g.at as [number, number]).addTo(map);
		});
		return () => placed.forEach((mk) => mk.remove());
	});
</script>

<style>
	:global(.anchor) {
		width: 18px;
		height: 18px;
		border-radius: 9999px;
		border: 3px solid var(--alvyo-route);
		background: #fff;
		box-shadow: 0 1px 3px rgb(0 0 0 / 0.4);
		cursor: grab;
		font:
			600 10px/12px system-ui,
			sans-serif;
		color: #581c87;
		text-align: center;
	}
	:global(.ghost) {
		width: 14px;
		height: 14px;
		border-radius: 9999px;
		border: 3px solid #5d6a62;
		background: #dce3dc;
		opacity: 0.9;
	}
	:global(.through) {
		width: 10px;
		height: 10px;
		border-radius: 9999px;
		border: 2px solid var(--alvyo-route);
		background: #fff;
		cursor: default;
	}
	:global(.midpoint) {
		width: 14px;
		height: 14px;
		border-radius: 9999px;
		border: 3px solid var(--alvyo-route);
		background: #fff;
		box-shadow: 0 1px 2px rgb(0 0 0 / 0.3);
		cursor: grab;
	}
	:global(.anchor-start) {
		background: #16a34a;
		border-color: #fff;
	}
	:global(.anchor-end) {
		background: var(--alvyo-route);
		border-color: #fff;
	}
</style>
