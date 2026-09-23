import { SvelteMap } from 'svelte/reactivity';
import type { Leg } from '$lib/api/client';
import { combine, legKey, reverseLeg, totals, type Profile } from './route';

/** A point the user placed; `straight` applies to the leg arriving here. */
export type Anchor = { id: number; lon: number; lat: number; straight: boolean };

export type LegRequest = {
	from: { lon: number; lat: number };
	to: { lon: number; lat: number };
	profile: Profile;
	straight: boolean;
};

/** Why a leg failed, by HTTP status (see messages in the UI). */
export class LegError extends Error {
	constructor(public status: number) {
		super(`leg failed with status ${status}`);
	}
}

export type LegSlot =
	| { key: string; state: 'loading' }
	| { key: string; state: 'ok'; leg: Leg }
	| { key: string; state: 'error'; status: number };

export type FetchLeg = (req: LegRequest) => Promise<Leg>;

/** What a route stores of the planner: enough to resume editing. */
export type PlannerContent = {
	profile: Profile;
	anchors: { lon: number; lat: number; straight?: boolean }[];
	legs: Leg[];
};

type Snapshot = { anchors: Anchor[]; profile: Profile };

const HISTORY_LIMIT = 100;

/**
 * Route planning state. Legs are cached by their inputs, so moving an anchor
 * only recomputes its two adjacent legs, and undo/redo or reversing the route
 * needs no requests at all.
 */
export class Planner {
	anchors = $state<Anchor[]>([]);
	profile = $state<Profile>('hike');
	canUndo = $state(false);
	canRedo = $state(false);

	#cache = new SvelteMap<string, LegSlot>();
	// Bookkeeping for idle(), not UI state.
	// eslint-disable-next-line svelte/prefer-svelte-reactivity
	#inflight = new Set<Promise<void>>();
	#past: Snapshot[] = [];
	#future: Snapshot[] = [];
	#nextId = 1;
	#fetchLeg: FetchLeg;
	#savedFingerprint = $state('[]');

	constructor(fetchLeg: FetchLeg) {
		this.#fetchLeg = fetchLeg;
	}

	/** One slot per leg between consecutive anchors. */
	legs = $derived.by((): LegSlot[] =>
		this.anchors.slice(1).map((to, i) => {
			const key = this.#key(this.anchors[i], to);
			return this.#cache.get(key) ?? { key, state: 'loading' };
		})
	);
	readyLegs = $derived(this.legs.flatMap((l) => (l.state === 'ok' ? [l.leg] : [])));
	complete = $derived(this.legs.length > 0 && this.legs.every((l) => l.state === 'ok'));
	/** Changed since the last load() or markSaved(). */
	dirty = $derived(this.#fingerprint() !== this.#savedFingerprint);
	totals = $derived(totals(this.readyLegs));
	line = $derived(combine(this.readyLegs));

	/** Resumes a saved route; its legs are reused as computed. */
	load(c: PlannerContent) {
		this.profile = c.profile;
		this.anchors = c.anchors.map((a) => ({
			...this.#anchor(a.lon, a.lat),
			straight: a.straight ?? false
		}));
		c.legs.forEach((leg, i) => {
			const key = this.#key(this.anchors[i], this.anchors[i + 1]);
			this.#cache.set(key, { key, state: 'ok', leg });
		});
		this.#past = [];
		this.#future = [];
		this.#sync();
		this.markSaved();
	}

	/** The route to save; only meaningful when `complete`. */
	content(): PlannerContent {
		return {
			profile: this.profile,
			anchors: this.anchors.map((a) => ({ lon: a.lon, lat: a.lat, straight: a.straight })),
			legs: this.readyLegs
		};
	}

	markSaved() {
		this.#savedFingerprint = this.#fingerprint();
	}

	add(lon: number, lat: number) {
		this.#change(() => this.anchors.push(this.#anchor(lon, lat)));
	}

	/** Inserts an anchor before position `index` (e.g. when dragging a leg). */
	insert(index: number, lon: number, lat: number) {
		this.#change(() => this.anchors.splice(index, 0, this.#anchor(lon, lat)));
	}

	move(id: number, lon: number, lat: number) {
		this.#change(() => {
			const a = this.anchors.find((x) => x.id === id);
			if (a) Object.assign(a, { lon, lat });
		});
	}

	remove(id: number) {
		this.#change(() => {
			this.anchors = this.anchors.filter((a) => a.id !== id);
			if (this.anchors[0]) this.anchors[0].straight = false;
		});
	}

	/** Draws leg `index` (between anchors index and index+1) as a straight line. */
	setStraight(index: number, straight: boolean) {
		this.#change(() => {
			const to = this.anchors[index + 1];
			if (to) to.straight = straight;
		});
	}

	setProfile(profile: Profile) {
		if (profile !== this.profile) this.#change(() => (this.profile = profile));
	}

	/** Walk the route the other way round. */
	reverse() {
		this.#change(() => {
			const rev = [...this.anchors].reverse();
			// The straight flag belongs to the leg's end, which is now its start.
			const flags = rev.map((_, i) => (i === 0 ? false : rev[i - 1].straight));
			this.anchors = rev.map((a, i) => ({ ...a, straight: flags[i] }));
		});
	}

	clear() {
		this.#change(() => (this.anchors = []));
	}

	undo() {
		const prev = this.#past.pop();
		if (!prev) return;
		this.#future.push(this.#snapshot());
		this.#restore(prev);
	}

	redo() {
		const next = this.#future.pop();
		if (!next) return;
		this.#past.push(this.#snapshot());
		this.#restore(next);
	}

	/** Resolves once no leg requests are running (for tests and saving). */
	async idle(): Promise<void> {
		while (this.#inflight.size > 0) await Promise.all(this.#inflight);
	}

	#fingerprint(): string {
		return JSON.stringify([this.profile, this.anchors.map((a) => [a.lon, a.lat, a.straight])]);
	}

	#anchor(lon: number, lat: number): Anchor {
		return { id: this.#nextId++, lon, lat, straight: false };
	}

	#key(from: Anchor, to: Anchor) {
		return legKey(from, to, to.straight, this.profile);
	}

	#change(fn: () => void) {
		this.#past.push(this.#snapshot());
		if (this.#past.length > HISTORY_LIMIT) this.#past.shift();
		this.#future = [];
		fn();
		this.#sync();
	}

	#snapshot(): Snapshot {
		return { anchors: this.anchors.map((a) => ({ ...a })), profile: this.profile };
	}

	#restore(s: Snapshot) {
		this.anchors = s.anchors.map((a) => ({ ...a }));
		this.profile = s.profile;
		this.#sync();
	}

	/** Requests legs that are not cached yet. */
	#sync() {
		this.canUndo = this.#past.length > 0;
		this.canRedo = this.#future.length > 0;
		for (let i = 1; i < this.anchors.length; i++) {
			const from = this.anchors[i - 1];
			const to = this.anchors[i];
			const key = this.#key(from, to);
			if (this.#cache.has(key)) continue;

			const reversed = this.#cache.get(legKey(to, from, to.straight, this.profile));
			if (reversed?.state === 'ok') {
				this.#cache.set(key, { key, state: 'ok', leg: reverseLeg(reversed.leg) });
				continue;
			}
			this.#cache.set(key, { key, state: 'loading' });
			const req: LegRequest = {
				from: { lon: from.lon, lat: from.lat },
				to: { lon: to.lon, lat: to.lat },
				profile: this.profile,
				straight: to.straight
			};
			const p = this.#fetchLeg(req).then(
				(leg) => void this.#cache.set(key, { key, state: 'ok', leg }),
				(err) => {
					this.#cache.set(key, {
						key,
						state: 'error',
						status: err instanceof LegError ? err.status : 0
					});
				}
			);
			this.#inflight.add(p);
			p.finally(() => this.#inflight.delete(p));
		}
	}
}
