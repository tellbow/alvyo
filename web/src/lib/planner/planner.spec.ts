import { describe, expect, it } from 'vitest';
import { LegError, Planner, type LegRequest } from './planner.svelte';
import { fakeLeg } from './testing';

function setup(fail?: (req: LegRequest) => boolean) {
	const calls: LegRequest[] = [];
	const planner = new Planner(async (req) => {
		calls.push(req);
		if (fail?.(req)) throw new LegError(422);
		return fakeLeg([
			[req.from.lon, req.from.lat, 500],
			[req.to.lon, req.to.lat, 600]
		]);
	});
	return { planner, calls };
}

describe('Planner', () => {
	it('only requests legs whose inputs changed', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		await p.idle();
		expect(calls).toHaveLength(2);
		expect(p.complete).toBe(true);
		expect(p.totals.distanceM).toBe(2000);

		p.move(p.anchors[1].id, 8.15, 46.15); // both adjacent legs
		await p.idle();
		expect(calls).toHaveLength(4);

		p.move(p.anchors[2].id, 8.25, 46.25); // only the last leg
		await p.idle();
		expect(calls).toHaveLength(5);
	});

	it('undo, redo and reverse reuse computed legs', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		p.move(p.anchors[2].id, 8.3, 46.3);
		await p.idle();
		const before = calls.length;

		p.undo();
		expect(p.anchors[2].lon).toBe(8.2);
		p.redo();
		expect(p.anchors[2].lon).toBe(8.3);
		p.reverse();
		await p.idle();
		expect(calls).toHaveLength(before);
		expect(p.complete).toBe(true);
		expect(p.anchors[0].lon).toBe(8.3);
		// reversed leg swaps climbs and times
		expect(p.totals.ascentM).toBe(40);
		expect(p.totals.durationS).toBe(1800);
	});

	it('draws a leg straight on request and keeps the flag when reversing', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		p.setStraight(1, true);
		await p.idle();
		expect(calls.at(-1)?.straight).toBe(true);
		p.reverse();
		expect(p.anchors.map((a) => a.straight)).toEqual([false, true, false]);
	});

	it('reports failed legs and recovers when the anchor moves', async () => {
		const { planner: p } = setup((req) => req.to.lon > 9);
		p.add(8.0, 46.0);
		p.add(9.5, 46.1);
		await p.idle();
		expect(p.legs[0]).toMatchObject({ state: 'error', status: 422 });
		expect(p.complete).toBe(false);

		p.move(p.anchors[1].id, 8.5, 46.1);
		await p.idle();
		expect(p.legs[0].state).toBe('ok');
	});

	it('joins neighbours directly when an anchor is removed', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		await p.idle();
		p.remove(p.anchors[1].id);
		await p.idle();
		expect(calls).toHaveLength(3);
		expect(calls.at(-1)).toMatchObject({ from: { lon: 8.0 }, to: { lon: 8.2 } });
	});

	it('resumes a saved route without routing again', async () => {
		const first = setup();
		first.planner.add(8.0, 46.0);
		first.planner.add(8.1, 46.1);
		first.planner.setStraight(0, true);
		await first.planner.idle();
		const saved = first.planner.content();

		const { planner: p, calls } = setup();
		p.load(saved);
		await p.idle();
		expect(calls).toHaveLength(0);
		expect(p.complete).toBe(true);
		expect(p.dirty).toBe(false);
		expect(p.canUndo).toBe(false);
		expect(p.anchors[1].straight).toBe(true);

		p.add(8.2, 46.2);
		expect(p.dirty).toBe(true);
		p.markSaved();
		expect(p.dirty).toBe(false);
	});
});
