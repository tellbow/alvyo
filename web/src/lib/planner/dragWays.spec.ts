import { describe, expect, it } from 'vitest';
import { distinctPoint, nearestWay, otherWays, sameWay, type Way } from './dragWays';

// Along 46.66° N, and one bulging north to 46.67°.
const straight: Way = Array.from({ length: 21 }, (_, i) => [8 + i * 0.001, 46.66]);
const north: Way = Array.from({ length: 21 }, (_, i) => [
	8 + i * 0.001,
	46.66 + 0.01 * Math.sin((i / 20) * Math.PI)
]);

describe('dragging a leg onto another way', () => {
	it('knows the way the leg takes from the others', () => {
		const leg = straight.map(([lon, lat]) => [lon, lat + 0.00005, 500]); // 5 m off, with heights
		expect(sameWay(straight, leg)).toBe(true);
		expect(sameWay(north, leg)).toBe(false);
		expect(otherWays([straight, north], leg).map((w) => w.index)).toEqual([1]);
		// A leg not computed yet: every way is another.
		expect(otherWays([straight, north], [])).toHaveLength(2);
	});

	it('finds the way under the pointer, in pixels', () => {
		// 1° = 10 000 px, y downwards.
		const project = ([lon, lat]: [number, number]) => ({ x: lon * 10_000, y: -lat * 10_000 });
		const ways = otherWays([straight, north], []);
		const top = project(north[10]);
		const hit = nearestWay(ways, { x: top.x + 3, y: top.y + 4 }, project)!;
		expect(hit.way.index).toBe(1);
		expect(hit.point).toEqual(north[10]);
		expect(hit.px).toBeCloseTo(5);
		expect(nearestWay([], top, project)).toBeUndefined();
	});

	it('sends the point where the chosen way is farthest from the others', () => {
		expect(distinctPoint(north, [straight])).toEqual(north[10]);
		// Sharing its first half with the straight way: a point in the other half.
		const half: Way = [...straight.slice(0, 11), ...north.slice(11)];
		const p = distinctPoint(half, [straight]);
		expect(half.indexOf(p)).toBeGreaterThan(10);
	});
});
