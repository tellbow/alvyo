import type { APIRequestContext } from '@playwright/test';
import { linkFromMail } from './mailpit';

/** Signs up through the API and confirms the address with the e-mailed
 * link, which logs the request context in (signing up alone does not);
 * the answer of the confirmation, 200 with the user. */
export async function signUp(
	request: APIRequestContext,
	options: { data: { email: string; username: string; [key: string]: unknown } }
) {
	const res = await request.post('/api/v1/auth/signup', options);
	if (res.status() !== 202) throw new Error(`signup: ${res.status()} ${await res.text()}`);
	const token = new URL(await linkFromMail(options.data.email, '/verify-email')).searchParams.get(
		'token'
	);
	return request.post('/api/v1/auth/verify-email', { data: { token } });
}
