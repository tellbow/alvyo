<script lang="ts">
	import { ROUTE_COLOR } from './colors';
	import type {
		FilterSpecification,
		GeoJSONSource,
		Map as MapLibreMap,
		MapLayerMouseEvent,
		MapLayerTouchEvent,
		MapMouseEvent,
		MapTouchEvent,
		Marker
	} from 'maplibre-gl';
	import type * as MapLibre from 'maplibre-gl';
	import { api } from '#lib/api/client.js';
	import { ROUTE_PREFIX } from '#lib/map/styles.js';
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
		ghosts = [],
		dragPath = false,
		onnotice
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
		/** dragging the line moves the leg onto another path instead of adding a point (Alt flips it) */
		dragPath?: boolean;
		/** a message for the user, e.g. that there is no other way */
		onnotice?: (text: string) => void;
	} = $props();

	const LEGS = `${ROUTE_PREFIX}legs`;
	const HOVER = `${ROUTE_PREFIX}hover`;
	/** Dashed lines to the neighbouring points while a point or the line is dragged. */
	const DRAG = `${ROUTE_PREFIX}drag`;
	/** The other ways of a leg while it is dragged onto another path. */
	const WAYS = `${ROUTE_PREFIX}ways`;
	/** How close to another way the line is let go to take it, in pixels. */
	const REACH_PX = 40;
	/** Layers that count as "the route" for clicks. */
	export const LINE_LAYERS = [`${ROUTE_PREFIX}line`, `${ROUTE_PREFIX}line-straight`];
	const COLOR = ROUTE_COLOR;
	/** How long a finger rests on the line before it takes the line. */
	const HOLD_MS = 400;

	const empty = { type: 'FeatureCollection' as const, features: [] };

	function addLayers() {
		if (map.getSource(LEGS)) return; // carried over from the previous base map
		map.addSource(LEGS, {
			type: 'geojson',
			data: empty,
			attribution: '© OpenStreetMap contributors'
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
		const onEnter = () => (map.getCanvas().style.cursor = editable ? 'pointer' : '');
		const onLeave = () => (map.getCanvas().style.cursor = '');
		// Press on the line and drag: a new point where it is released, between
		// the ends of that leg; or (dragPath, or Alt held) the leg onto another
		// way between them, which show while dragging. A click without
		// dragging is handled by the planner.
		const drag = (leg: number) => {
			// A straight line has no path to move onto.
			const onPath = (path: boolean) => path && !planner.anchors[leg + 1]?.straight;
			let ways: Promise<Ways | undefined> | undefined;
			let got: Ways | undefined;
			const fetch = () => (ways ??= waysOf(leg).then((w) => (got = w)));
			return {
				move(at: [number, number], path: boolean) {
					if (!onPath(path)) {
						showWays();
						band(at, leg, leg + 1);
						return;
					}
					band();
					void fetch();
					const near = got && nearestWay(got.others, map.project(at), (p) => map.project(p));
					showWays(got?.others, near && near.px <= REACH_PX ? near.way.index : undefined);
				},
				async end(at: [number, number], path: boolean) {
					band();
					if (!onPath(path)) {
						showWays();
						planner.insert(leg + 1, at[0], at[1]);
						return;
					}
					const [from, to] = [planner.anchors[leg], planner.anchors[leg + 1]];
					const w = await fetch();
					showWays();
					// Points added, moved or undone meanwhile: the leg is another.
					if (planner.anchors[leg] !== from || planner.anchors[leg + 1] !== to) return;
					if (!w) return onnotice?.(m.plan_drag_failed());
					if (w.others.length === 0) return onnotice?.(m.plan_drag_none());
					const near = nearestWay(w.others, map.project(at), (p) => map.project(p));
					if (!near || near.px > REACH_PX) return onnotice?.(m.plan_drag_off());
					// The shortest way is the leg without a shape.
					if (near.way.index === 0) planner.unshape(leg);
					else {
						const p = distinctPoint(
							near.way.way,
							w.all.filter((_, i) => i !== near.way.index)
						);
						planner.reroute(leg, p[0], p[1]);
					}
				},
				cancel() {
					band();
					showWays();
				}
			};
		};
		const onDown = (e: MapLayerMouseEvent) => {
			const leg = Number(e.features?.[0]?.properties?.leg);
			// Presses on a point's marker reach the map too; the marker drags itself.
			if (e.originalEvent.target !== map.getCanvas()) return;
			if (!editable || e.originalEvent.button !== 0 || Number.isNaN(leg)) return;
			e.preventDefault(); // no map panning
			const start = e.point;
			const d = drag(leg);
			let at: [number, number] | undefined;
			const onMove = (ev: MapMouseEvent) => {
				if (!at && ev.point.dist(start) < 3) return; // MapLibre's click tolerance
				at = [ev.lngLat.lng, ev.lngLat.lat];
				map.getCanvas().style.cursor = 'grabbing';
				d.move(at, dragPath !== ev.originalEvent.altKey);
			};
			const onUp = (ev: MouseEvent) => {
				map.off('mousemove', onMove);
				// A click leaves the pointer on the line: its cursor stays.
				if (!at) return d.cancel();
				map.getCanvas().style.cursor = '';
				void d.end(at, dragPath !== ev.altKey);
			};
			map.on('mousemove', onMove);
			window.addEventListener('mouseup', onUp, { once: true });
		};
		// On a touch screen a finger on the line pans the map, as elsewhere;
		// held still for a moment, it takes the line instead.
		const onTouch = (e: MapLayerTouchEvent) => {
			const leg = Number(e.features?.[0]?.properties?.leg);
			if (!editable || e.points.length !== 1 || Number.isNaN(leg)) return;
			const start = e.point;
			const d = drag(leg);
			let dragging = false;
			let at: [number, number] | undefined;
			const hold = setTimeout(() => {
				dragging = true;
				map.dragPan.disable(); // also ends the pan gesture begun
				at = [e.lngLat.lng, e.lngLat.lat];
				d.move(at, dragPath);
				navigator.vibrate?.(10);
			}, HOLD_MS);
			const onMove = (ev: MapTouchEvent) => {
				if (!dragging) {
					// Moved or pinched before the hold: the map's gesture.
					if (ev.points.length !== 1 || ev.point.dist(start) > 10) end();
					return;
				}
				ev.preventDefault();
				at = [ev.lngLat.lng, ev.lngLat.lat];
				d.move(at, dragPath);
			};
			const end = () => {
				clearTimeout(hold);
				map.off('touchmove', onMove);
				map.off('touchend', onEnd);
				map.off('touchcancel', end);
				if (dragging) map.dragPan.enable();
			};
			const onEnd = () => {
				const done = dragging && at;
				end();
				if (done) void d.end(at!, dragPath);
				else d.cancel();
			};
			map.on('touchmove', onMove);
			map.on('touchend', onEnd);
			map.on('touchcancel', end);
		};
		for (const id of LINE_LAYERS) {
			map.on('mouseenter', id, onEnter);
			map.on('mouseleave', id, onLeave);
			map.on('mousedown', id, onDown);
			map.on('touchstart', id, onTouch);
		}
		return () => {
			map.off('style.load', onStyle);
			for (const id of LINE_LAYERS) {
				map.off('mouseenter', id, onEnter);
				map.off('mouseleave', id, onLeave);
				map.off('mousedown', id, onDown);
				map.off('touchstart', id, onTouch);
			}
		};
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
	:global(.anchor-start) {
		background: #16a34a;
		border-color: #fff;
	}
	:global(.anchor-end) {
		background: var(--alvyo-route);
		border-color: #fff;
	}
</style>
