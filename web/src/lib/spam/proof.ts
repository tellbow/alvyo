import { api } from '#lib/api/client.js';

type Proof = { challenge: string; nonce: string };

const stale = 25 * 60_000; // the API takes a challenge for 30 minutes

/** Whether the SHA-256 of «challenge:nonce» starts with that many zero bits. */
export function hasZeroBits(hash: Uint8Array, bits: number) {
	for (let i = 0; i < bits; i++) if (hash[i >> 3] & (0x80 >> (i & 7))) return false;
	return true;
}

export async function solve(challenge: string, bits: number) {
	const enc = new TextEncoder();
	for (let nonce = 0; ; nonce++) {
		const hash = await crypto.subtle.digest('SHA-256', enc.encode(`${challenge}:${nonce}`));
		if (hasZeroBits(new Uint8Array(hash), bits)) return String(nonce);
	}
}

async function fresh(): Promise<Proof> {
	const { data } = await api().POST('/challenge');
	if (!data) throw new Error('no challenge');
	const [nonce] = await Promise.all([
		solve(data.challenge, data.bits),
		new Promise((done) => setTimeout(done, data.wait_ms))
	]);
	return { challenge: data.challenge, nonce };
}

/**
 * What an open form sends along against bots: a challenge answered while the
 * person types, and the trap field (`Trap.svelte`). `start` when the form
 * opens; `take` when it is sent, once per sending.
 */
export function formProof() {
	let next: Promise<Proof> | undefined;
	let at = 0;
	function start() {
		if (next && Date.now() - at < stale) return next;
		at = Date.now();
		next = fresh();
		next.catch(() => (next = undefined)); // the next try asks again
		return next;
	}
	return {
		start,
		async take(e: SubmitEvent) {
			const website = new FormData(e.target as HTMLFormElement).get('website')?.toString() ?? '';
			const proof = await start().catch(() => ({ challenge: '', nonce: '' }));
			next = undefined;
			return { ...proof, website };
		}
	};
}
