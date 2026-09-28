import { SvelteMap } from 'svelte/reactivity';
import type { Leg } from '$lib/api/client';
import { combine, legKey, reverseLeg, totals, type Profile } from './route';

type LonLat = { lon: number; lat: number };

/**
 * A point the user placed; `straight`, `alpine` (the alpine profile on a
 * hike route) and `through` (where the line was dragged onto another path)
 * apply to the leg arriving here, and `name` is the place it was found as by
 * search.
 */
export type Anchor = {
	id: number;
	lon: number;
	lat: number;
	straight: boolean;
	alpine?: boolean;
	through?: LonLat;
	name?: string;
};

export type LegRequest = {
	from: { lon: number; lat: number };
	to: { lon: number; lat: number };
	profile: Profile;
	straight: boolean;
	through?: LonLat;
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
	anchors: {
		lon: number;
		lat: number;
		straight?: boolean;
		alpine?: boolean;
		through?: LonLat;
		name?: string;
	}[];
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

	/** The height of the anchor at `i` on its computed legs, if known. */
	height(i: number): number | undefined {
		const before = this.legs[i - 1];
		if (before?.state === 'ok') return before.leg.coordinates.at(-1)?.[2];
		const after = this.legs[i];
		if (after?.state === 'ok') return after.leg.coordinates[0]?.[2];
		return undefined;
	}

	/** Resumes a saved route; its legs are reused as computed. */
	load(c: PlannerContent) {
		this.profile = c.profile;
		this.anchors = c.anchors.map((a) => ({
			...this.#anchor(a.lon, a.lat, a.name),
			straight: a.straight ?? false,
			...(a.alpine ? { alpine: true } : {}),
			...(a.through ? { through: a.through } : {})
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
			anchors: this.anchors.map((a) => ({
				lon: a.lon,
				lat: a.lat,
				straight: a.straight,
				...(a.alpine ? { alpine: true } : {}),
				...(a.through ? { through: a.through } : {}),
				...(a.name ? { name: a.name } : {})
			})),
			legs: this.readyLegs
		};
	}

	/** What the route is now, to mark as saved once the server has it. */
	fingerprint(): string {
		return this.#fingerprint();
	}

	/** Marks the route as saved: as it was when fingerprinted (changes made
	 * while saving stay unsaved), or as it is. */
	markSaved(fingerprint = this.#fingerprint()) {
		this.#savedFingerprint = fingerprint;
	}

	add(lon: number, lat: number, name?: string) {
		this.#change(() => this.anchors.push(this.#anchor(lon, lat, name)));
	}

	/** Inserts an anchor before position `index` (e.g. when dragging a leg);
	 * both halves of a straight or alpine leg stay so. */
	insert(index: number, lon: number, lat: number) {
		const straight = this.anchors[index]?.straight ?? false;
		const alpine = this.anchors[index]?.alpine;
		this.#change(() => {
			this.anchors.splice(index, 0, {
				...this.#anchor(lon, lat),
				straight,
				...(alpine ? { alpine } : {})
			});
			delete this.anchors[index + 1]?.through; // the new point shapes the leg now
		});
	}

	/** Moves leg `index` onto the path closest to lon/lat, without a new point. */
	reroute(index: number, lon: number, lat: number) {
		this.#change(() => {
			const to = this.anchors[index + 1];
			if (to) to.through = { lon, lat };
		});
	}

	/** Lets leg `index` take the shortest path again. */
	unshape(index: number) {
		this.#change(() => delete this.anchors[index + 1]?.through);
	}

	/** Asks again for the legs that failed for a passing reason. */
	retry() {
		this.#sync();
	}

	/** Moves an anchor on the map; it is no longer the place it was found as. */
	move(id: number, lon: number, lat: number) {
		this.#change(() => {
			const a = this.anchors.find((x) => x.id === id);
			if (a) Object.assign(a, { lon, lat, name: undefined });
		});
	}

	/** Moves the anchor at `from` to position `to` in the order. */
	reorder(from: number, to: number) {
		if (to < 0 || to >= this.anchors.length || from === to) return;
		this.#change(() => {
			const before = this.#previous();
			const [a] = this.anchors.splice(from, 1);
			this.anchors.splice(to, 0, a);
			this.anchors[0].straight = false;
			delete this.anchors[0].alpine;
			this.#dropStaleThrough(before);
		});
	}

	remove(id: number) {
		this.#change(() => {
			const before = this.#previous();
			this.anchors = this.anchors.filter((a) => a.id !== id);
			if (this.anchors[0]) {
				this.anchors[0].straight = false;
				delete this.anchors[0].alpine;
			}
			this.#dropStaleThrough(before);
		});
	}

	/** Draws leg `index` (between anchors index and index+1) as a straight line. */
	setStraight(index: number, straight: boolean) {
		this.#change(() => {
			const to = this.anchors[index + 1];
			if (to) to.straight = straight;
		});
	}

	/** Plans leg `index` with the alpine profile on a hike route (or not). */
	setAlpine(index: number, alpine: boolean) {
		this.#change(() => {
			const to = this.anchors[index + 1];
			if (to && alpine) to.alpine = true;
			else if (to) delete to.alpine;
		});
	}

	setProfile(profile: Profile) {
		if (profile !== this.profile) this.#change(() => (this.profile = profile));
	}

	/** Walk the route the other way round. */
	reverse() {
		this.#change(() => {
			const rev = [...this.anchors].reverse();
			// Straight, alpine and through belong to the leg's end, which is now
			// its start.
			this.anchors = rev.map((a, i) => ({
				...a,
				straight: rev[i - 1]?.straight ?? false,
				alpine: rev[i - 1]?.alpine,
				through: rev[i - 1]?.through
			}));
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
		return JSON.stringify([
			this.profile,
			this.anchors.map((a) => [a.lon, a.lat, a.straight, a.alpine ?? false, a.through, a.name])
		]);
	}

	#anchor(lon: number, lat: number, name?: string): Anchor {
		return { id: this.#nextId++, lon, lat, straight: false, name };
	}

	#key(from: Anchor, to: Anchor) {
		return legKey(from, to, to.straight, this.#profileOf(to), to.through);
	}

	/** The profile of the leg arriving at `to`. */
	#profileOf(to: Anchor): Profile {
		return to.alpine ? 'alpine' : this.profile;
	}

	/** Each anchor's predecessor, by id. */
	#previous() {
		// eslint-disable-next-line svelte/prefer-svelte-reactivity -- a local lookup, not state
		return new Map(this.anchors.map((a, i) => [a.id, this.anchors[i - 1]?.id]));
	}

	/** A leg that now starts elsewhere forgets the path it was dragged onto. */
	#dropStaleThrough(before: Map<number, number | undefined>) {
		this.anchors.forEach((a, i) => {
			if (before.get(a.id) !== this.anchors[i - 1]?.id) delete a.through;
		});
	}

	#change(fn: () => void) {
		this.#past.push(this.#snapshot());
		if (this.#past.length > HISTORY_LIMIT) this.#past.shift();
		this.#future = [];
		fn();
		this.#sync();
	}

	#snapshot(): Snapshot {
		return {
			anchors: this.anchors.map((a) => ({ ...a, through: a.through && { ...a.through } })),
			profile: this.profile
		};
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
			const cached = this.#cache.get(key);
			// Kept, except failures that may pass (no path nearby will not).
			if (cached && !(cached.state === 'error' && cached.status !== 422)) continue;

			const reversed = this.#cache.get(
				legKey(to, from, to.straight, this.#profileOf(to), to.through)
			);
			if (reversed?.state === 'ok') {
				this.#cache.set(key, { key, state: 'ok', leg: reverseLeg(reversed.leg) });
				continue;
			}
			this.#cache.set(key, { key, state: 'loading' });
			const req: LegRequest = {
				from: { lon: from.lon, lat: from.lat },
				to: { lon: to.lon, lat: to.lat },
				profile: this.#profileOf(to),
				straight: to.straight,
				...(to.through && !to.straight ? { through: to.through } : {})
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
