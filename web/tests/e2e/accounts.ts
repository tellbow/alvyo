import { createHash } from 'node:crypto';
import type { APIRequestContext } from '@playwright/test';
import { linkFromMail } from './mailpit';

/** What the forms send along against bots, for tests that post directly. */
export async function spamProof(request: APIRequestContext) {
	const { challenge, bits } = await (await request.post('/api/v1/challenge')).json();
	for (let nonce = 0; ; nonce++) {
		const hash = createHash('sha256').update(`${challenge}:${nonce}`).digest();
		let zero = true;
		for (let i = 0; i < bits; i++) if (hash[i >> 3] & (0x80 >> (i & 7))) zero = false;
		if (zero) return { challenge, nonce: String(nonce) };
	}
}

/** Signs up through the API and confirms the address with the e-mailed
 * link, which logs the request context in (signing up alone does not);
 * the answer of the confirmation, 200 with the user. */
export async function signUp(
	request: APIRequestContext,
	options: { data: { email: string; username: string; [key: string]: unknown } }
) {
	const res = await request.post('/api/v1/auth/signup', {
		data: { ...options.data, ...(await spamProof(request)) }
	});
	if (res.status() !== 202) throw new Error(`signup: ${res.status()} ${await res.text()}`);
	const token = new URL(await linkFromMail(options.data.email, '/verify-email')).searchParams.get(
		'token'
	);
	return request.post('/api/v1/auth/verify-email', { data: { token } });
}
