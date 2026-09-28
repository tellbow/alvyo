import { describe, expect, it } from 'vitest';
import type { Home, Journey, JourneyStage, Place } from '$lib/api/client';
import { journeyEnds, travelQuery, tripLines } from './travel';

const stop = (name: string, ref: string, at: number[]): Place => ({
	id: name,
	kind: 'pt_stop',
	name,
	detail: '',
	at,
	distance_m: 0,
	ref
});
const hut = (name: string, at: number[]): Place => ({
	id: name,
	kind: 'hut',
	name,
	detail: '',
	at,
	distance_m: 0
});

function stage(
	start: Place | null,
	end: Place | null,
	line: number[][] | null,
	date: string | null
): JourneyStage {
	return {
		start_place: start,
		end_place: end,
		planned_date: date,
		route: line && { id: 'r', line, start: line[0], end: line.at(-1)!, totals: {} }
	} as unknown as JourneyStage;
}

const home: Home = {
	id: 'h',
	name: 'Zuhause',
	address: 'Länggasse 13B, 3600 Thun',
	lon: 7.6197,
	lat: 46.764
};

describe('travel', () => {
	it("meets a journey at the first stage's stop and leaves it from the last, on their days", () => {
		const j = {
			stage_list: [
				stage(null, null, null, null), // no route yet
				stage(
					stop('Spiez', '8507483', [7.68, 46.69]),
					hut('Hütte', [7.7, 46.6]),
					[
						[7.68, 46.69],
						[7.7, 46.6]
					],
					'2026-07-04'
				),
				stage(
					hut('Hütte', [7.7, 46.6]),
					null,
					[
						[7.7, 46.6],
						[7.74831, 46.02449]
					],
					'2026-07-06'
				)
			]
		} as Journey;
		const { start, end } = journeyEnds(j, { start: 'Start der Tour', end: 'Ende der Tour' });
		expect(start).toEqual({ at: '8507483', name: 'Spiez', date: '2026-07-04' });
		// No stop at the end: the end of the line, which the planner walks to.
		expect(end).toEqual({ at: '7.74831,46.02449', name: 'Ende der Tour', date: '2026-07-06' });
	});

	it('asks for connections from home to the start, and from the end home', () => {
		const start = { at: '8507483', name: 'Spiez', date: '2026-07-04' };
		expect(travelQuery('to', home, start, { home_id: 'h', time: '06:00', arrive: false })).toEqual({
			from: '7.61970,46.76400',
			from_name: 'Zuhause',
			to: '8507483',
			date: '2026-07-04',
			time: '06:00',
			arrive: false,
			lines: true
		});
		const back = travelQuery(
			'back',
			home,
			{ at: '7.74831,46.02449', name: 'Zermatt', date: null },
			{ home_id: 'h', time: '20:00', arrive: true },
			'2026-09-28'
		);
		expect(back).toMatchObject({
			from: '7.74831,46.02449',
			from_name: 'Zermatt',
			to: '7.61970,46.76400',
			to_name: 'Zuhause',
			date: '2026-09-28',
			arrive: true
		});
	});

	it('draws the legs that have a way', () => {
		const lines = tripLines({
			start: '',
			end: '',
			transfers: 0,
			legs: [
				{
					kind: 'walk',
					from: 'Zuhause',
					to: 'Schwäbis',
					track: [
						[7.6, 46.7],
						[7.61, 46.71]
					]
				},
				{
					kind: 'ride',
					from: 'Thun',
					to: 'Spiez',
					line: 'S1',
					track: [
						[7.62, 46.75],
						[7.68, 46.69]
					]
				},
				{ kind: 'walk', from: 'Spiez', to: 'Spiez', duration_min: 2 }
			]
		});
		expect(lines.features.map((f) => f.properties?.kind)).toEqual(['walk', 'ride']);
		expect(tripLines(undefined).features).toEqual([]);
	});
});
