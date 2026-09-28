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

	it('knows the height of each point once its legs are computed', async () => {
		const { planner: p } = setup();
		p.add(8.0, 46.0);
		expect(p.height(0)).toBeUndefined();
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		await p.idle();
		expect([p.height(0), p.height(1), p.height(2)]).toEqual([500, 600, 600]);
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

	it('reorders points, reusing legs it already knows', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0, 'Start');
		p.add(8.1, 46.1);
		p.add(8.2, 46.2, 'Ziel');
		await p.idle();
		expect(calls).toHaveLength(2);

		p.reorder(2, 1); // the destination becomes the intermediate point
		await p.idle();
		expect(p.anchors.map((a) => a.name)).toEqual(['Start', 'Ziel', undefined]);
		// 8.2→8.1 is the known leg reversed; only 8.0→8.2 is new.
		expect(calls).toHaveLength(3);
		expect(p.complete).toBe(true);

		p.reorder(1, 0);
		expect(p.anchors[0].name).toBe('Ziel');
		expect(p.anchors[0].straight).toBe(false);
		p.reorder(0, -1); // out of range: nothing
		p.undo();
		expect(p.anchors.map((a) => a.name)).toEqual(['Start', 'Ziel', undefined]);
	});

	it('keeps names of points found by search until they are moved', async () => {
		const { planner: p } = setup();
		p.add(8.0, 46.0, 'Gitschenen');
		p.add(8.1, 46.1, 'Brisenhaus');
		await p.idle();
		expect(p.content().anchors).toEqual([
			{ lon: 8.0, lat: 46.0, straight: false, name: 'Gitschenen' },
			{ lon: 8.1, lat: 46.1, straight: false, name: 'Brisenhaus' }
		]);
		p.markSaved();
		p.move(p.anchors[1].id, 8.12, 46.1);
		expect(p.anchors[1].name).toBeUndefined();
		expect(p.dirty).toBe(true);

		const q = setup().planner;
		q.load(p.content());
		expect(q.anchors.map((a) => a.name)).toEqual(['Gitschenen', undefined]);
	});

	it('asks again for legs that failed for a passing reason, not for no path', async () => {
		let status = 503;
		const calls: LegRequest[] = [];
		const p = new Planner(async (req) => {
			calls.push(req);
			if (status) throw new LegError(status);
			return fakeLeg([
				[req.from.lon, req.from.lat, 500],
				[req.to.lon, req.to.lat, 600]
			]);
		});
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		await p.idle();
		expect(p.legs[0].state).toBe('error');

		status = 0; // the elevation service is back
		p.retry();
		await p.idle();
		expect(p.legs[0].state).toBe('ok');
		expect(calls).toHaveLength(2);

		status = 422;
		p.add(8.2, 46.2);
		await p.idle();
		p.retry();
		await p.idle();
		expect(p.legs[1].state).toBe('error');
		expect(calls).toHaveLength(3); // no path stays no path
	});

	it('splitting a straight leg keeps both halves straight', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.2, 46.2);
		p.setStraight(0, true);
		p.insert(1, 8.1, 46.1);
		await p.idle();
		expect(p.anchors.map((a) => a.straight)).toEqual([false, true, true]);
		expect(calls.slice(-2).every((c) => c.straight)).toBe(true);
	});

	it('changes made while saving stay unsaved', async () => {
		const { planner: p } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		await p.idle();
		const sent = p.fingerprint();
		p.add(8.2, 46.2); // while the request runs
		p.markSaved(sent);
		expect(p.dirty).toBe(true);
		p.markSaved();
		expect(p.dirty).toBe(false);
	});

	it('a leg dragged onto another path keeps it until its start changes', async () => {
		const { planner: p, calls } = setup();
		p.add(8.0, 46.0);
		p.add(8.1, 46.1);
		p.add(8.2, 46.2);
		await p.idle();
		p.reroute(0, 8.05, 46.06);
		await p.idle();
		expect(p.anchors).toHaveLength(3);
		expect(calls.at(-1)?.through).toEqual({ lon: 8.05, lat: 46.06 });
		expect(p.content().anchors[1].through).toEqual({ lon: 8.05, lat: 46.06 });
		expect(p.dirty).toBe(true);

		// Walked the other way, the same leg (now the second) keeps the path.
		const before = calls.length;
		p.reverse();
		await p.idle();
		expect(calls).toHaveLength(before);
		expect(p.anchors.map((a) => a.through)).toEqual([
			undefined,
			undefined,
			{ lon: 8.05, lat: 46.06 }
		]);
		p.undo();
		p.undo();
		expect(p.anchors[1].through).toBeUndefined();
		p.redo();

		// Moving the end keeps it; a new point in the leg or removing its start drops it.
		p.move(p.anchors[1].id, 8.11, 46.11);
		expect(p.anchors[1].through).toBeDefined();
		p.insert(1, 8.03, 46.03);
		expect(p.anchors[2].through).toBeUndefined();
		p.undo();
		p.remove(p.anchors[0].id);
		expect(p.anchors[0].through).toBeUndefined();
		p.undo();
		p.unshape(0);
		expect(p.anchors[1].through).toBeUndefined();
	});

	it('a saved route resumes with its dragged paths', () => {
		const { planner: p, calls } = setup();
		const leg = fakeLeg([
			[8.0, 46.0, 500],
			[8.1, 46.1, 600]
		]);
		p.load({
			profile: 'hike',
			anchors: [
				{ lon: 8.0, lat: 46.0 },
				{ lon: 8.1, lat: 46.1, through: { lon: 8.05, lat: 46.06 } }
			],
			legs: [leg]
		});
		expect(p.complete).toBe(true);
		expect(calls).toHaveLength(0);
		expect(p.dirty).toBe(false);
	});
});
