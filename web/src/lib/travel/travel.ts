import type { FeatureCollection, LineString } from 'geojson';
import type { Home, Journey, Place, Route, Travel, Trip, TravelWay } from '$lib/api/client';

/** Where public transport meets the hike: a stop, or a point on the line. */
export type End = {
	/** Didok number of a stop, for the timetable; else lon,lat. */
	at: string;
	name: string;
	/** The stage's day, YYYY-MM-DD; null if not planned (and for routes). */
	date: string | null;
};

/** Where a way starts or ends away from the hike: a home or another place. */
export type Spot = { name: string; lon: number; lat: number };

/** The home or place of a way. */
export function waySpot(way: TravelWay | undefined, homes: Home[]): Spot | undefined {
	return way?.place ?? homes.find((h) => h.id === way?.home_id);
}

const coords = (p: number[]) => `${p[0].toFixed(5)},${p[1].toFixed(5)}`;

function end(
	place: Place | null | undefined,
	point: number[],
	date: string | null,
	unnamed: string
): End {
	if (place?.kind === 'pt_stop' && place.ref) return { at: place.ref, name: place.name, date };
	return { at: coords(place?.at ?? point), name: place?.name || unnamed, date };
}

/**
 * The start of the first stage with a route and the end of the last: where
 * one travels to from home and back from. Points without a place get the
 * names given, for the walk to and from them.
 */
export function journeyEnds(
	j: Journey,
	names = { start: '', end: '' }
): { start?: End; end?: End } {
	const routed = j.stage_list.filter((s) => s.route);
	const first = routed[0];
	const last = routed.at(-1);
	return {
		start: first?.route
			? end(first.start_place, first.route.start, first.planned_date, names.start)
			: undefined,
		end: last?.route ? end(last.end_place, last.route.end, last.planned_date, names.end) : undefined
	};
}

/** A route's start and end, with the names of its first and last point. */
export function routeEnds(r: Route, names = { start: '', end: '' }): { start?: End; end?: End } {
	const first = r.legs[0]?.coordinates[0];
	const last = r.legs.at(-1)?.coordinates.at(-1);
	if (!first || !last) return {};
	return {
		start: end(null, first, null, r.anchors[0]?.name || names.start),
		end: end(null, last, null, r.anchors.at(-1)?.name || names.end)
	};
}

/**
 * The ways there and back that one has chosen, with the connections to ask
 * for on `date`: for a sheet to print.
 */
export function chosenWays(
	travel: Travel,
	homes: Home[],
	ends: { start?: End; end?: End },
	date: string
) {
	return (['to', 'back'] as const).flatMap((d) => {
		const way = travel[d];
		const spot = waySpot(way, homes);
		const at = d === 'to' ? ends.start : ends.end;
		if (!way || !spot || !at) return [];
		return [
			{
				direction: d,
				from: d === 'to' ? spot.name : at.name,
				to: d === 'to' ? at.name : spot.name,
				query: { ...travelQuery(d, spot, { ...at, date }, way), lines: false }
			}
		];
	});
}

/** Today in Switzerland, YYYY-MM-DD. */
export const swissToday = (now = new Date()) =>
	new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Zurich' }).format(now);

/**
 * `GET /connections` for the way from home (or another place) to the start
 * (to) or from the end home (back), with the ways to draw.
 */
export function travelQuery(
	direction: 'to' | 'back',
	home: Spot,
	at: End,
	way: TravelWay,
	today = swissToday()
) {
	const here = { place: `${home.lon.toFixed(5)},${home.lat.toFixed(5)}`, name: home.name };
	const there = { place: at.at, name: at.name };
	const [from, to] = direction === 'to' ? [here, there] : [there, here];
	return {
		from: from.place,
		to: to.place,
		// Names only for positions: stops have theirs.
		...(from.place.includes(',') && from.name ? { from_name: from.name.slice(0, 60) } : {}),
		...(to.place.includes(',') && to.name ? { to_name: to.name.slice(0, 60) } : {}),
		date: at.date ?? today,
		time: way.time,
		arrive: way.arrive,
		lines: true
	};
}

/** A trip's legs as lines: rides and walks, to draw apart from the hike. */
export function tripLines(trip: Trip | undefined): FeatureCollection<LineString> {
	return {
		type: 'FeatureCollection',
		features: (trip?.legs ?? [])
			.filter((l) => (l.track?.length ?? 0) > 1)
			.map((l) => ({
				type: 'Feature',
				properties: { kind: l.kind },
				geometry: { type: 'LineString', coordinates: l.track! }
			}))
	};
}
