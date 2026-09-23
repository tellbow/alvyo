import { describe, expect, it } from 'vitest';
import { combine, formatDuration, formatSAC, legKey, reverseLeg, totals } from './route';
import { fakeLeg } from './testing';

describe('legKey', () => {
	it('distinguishes direction, mode and profile', () => {
		const a = { lon: 8, lat: 46 };
		const b = { lon: 8.1, lat: 46.1 };
		const keys = new Set([
			legKey(a, b, false, 'hike'),
			legKey(b, a, false, 'hike'),
			legKey(a, b, true, 'hike'),
			legKey(a, b, false, 'alpine')
		]);
		expect(keys.size).toBe(4);
		expect(legKey(a, b, true, 'hike')).toBe(legKey(a, b, true, 'alpine'));
	});
});

describe('reverseLeg', () => {
	it('flips geometry, climbs, times and runs', () => {
		const leg = fakeLeg(
			[
				[0, 0, 1],
				[1, 0, 2],
				[2, 0, 3]
			],
			{
				details: {
					sac: [
						{ from: 0, to: 1, value: 'T1' },
						{ from: 1, to: 2, value: 'T3' }
					],
					surface: [],
					way_type: [],
					trail: []
				}
			}
		);
		const r = reverseLeg(leg);
		expect(r.coordinates[0]).toEqual([2, 0, 3]);
		expect([r.ascent_m, r.descent_m]).toEqual([20, 100]);
		expect([r.duration_s, r.duration_reverse_s]).toEqual([900, 1200]);
		expect(r.details.sac).toEqual([
			{ from: 0, to: 1, value: 'T3' },
			{ from: 1, to: 2, value: 'T1' }
		]);
		expect(reverseLeg(r)).toEqual(leg);
	});
});

describe('totals and combine', () => {
	it('sums legs and joins geometry without repeating joints', () => {
		const a = fakeLeg([
			[8, 46, 500],
			[8.001, 46, 510]
		]);
		const b = fakeLeg(
			[
				[8.001, 46, 510],
				[8.002, 46, 530]
			],
			{
				sac: { grade: 3, max: 3, breakdown: { T3: 1000 }, unofficial_m: 0 },
				details: { sac: [{ from: 0, to: 1, value: 'T3' }], surface: [], way_type: [], trail: [] }
			}
		);
		const t = totals([a, b]);
		expect(t.distanceM).toBe(2000);
		expect(t.durationS).toBe(2400);
		expect(formatSAC(t.sacGrade, t.sacMax)).toBe('T3');
		expect(t.trails.Bergwanderweg).toBe(2000);

		const c = combine([a, b]);
		expect(c.coordinates).toHaveLength(3);
		expect(c.distance[2]).toBeCloseTo(154.5, 0); // 2 × 0.001° lon at 46° N ≈ 2 × 77.2 m
		expect(c.sac).toEqual([
			{ from: 0, to: 1, value: 'T2' },
			{ from: 1, to: 2, value: 'T3' }
		]);
	});
});

describe('formatting', () => {
	it('rounds hiking times to 5 minutes like signposts', () => {
		expect(formatDuration(3 * 3600 + 23 * 60)).toBe('3 h 25 min');
		expect(formatDuration(3600)).toBe('1 h');
		expect(formatDuration(12 * 60)).toBe('10 min');
		expect(formatDuration(3600, 1.5)).toBe('1 h 30 min');
	});
	it('shows SAC ranges', () => {
		expect(formatSAC(2, 3)).toBe('T2–T3');
		expect(formatSAC(0, 0)).toBe('–');
	});
});
