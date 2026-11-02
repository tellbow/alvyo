import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { hasZeroBits, solve } from './proof';

describe('proof of work', () => {
	it('counts zero bits from the top', () => {
		expect(hasZeroBits(new Uint8Array([0x00, 0x7f]), 9)).toBe(true);
		expect(hasZeroBits(new Uint8Array([0x00, 0x7f]), 10)).toBe(false);
		expect(hasZeroBits(new Uint8Array([0x80]), 1)).toBe(false);
	});

	it('finds a nonce that the same hash elsewhere accepts', async () => {
		const nonce = await solve('salt.1.8.sig', 8);
		const hash = createHash('sha256').update(`salt.1.8.sig:${nonce}`).digest();
		expect(hash[0]).toBe(0);
	});
});
