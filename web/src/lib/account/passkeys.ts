import {
	browserSupportsWebAuthn,
	startAuthentication,
	startRegistration,
	type PublicKeyCredentialCreationOptionsJSON,
	type PublicKeyCredentialRequestOptionsJSON
} from '@simplewebauthn/browser';
import { api } from '#lib/api/client.js';

export { browserSupportsWebAuthn };

/** Why a passkey step failed, for the message shown. */
export type PasskeyProblem =
	'cancelled' | 'password' | 'login' | 'unverified' | 'again' | 'rejected' | 'other';

function problemOf(status: number, detail = ''): PasskeyProblem {
	if (status === 403) {
		if (detail.startsWith('confirm your e-mail')) return 'unverified';
		if (detail.startsWith('log in again')) return 'login'; // accounts without password
		return 'password';
	}
	return status === 409 ? 'again' : status === 422 ? 'rejected' : 'other';
}

/** Logs in with a passkey the browser offers; undefined on success. */
export async function loginWithPasskey(): Promise<PasskeyProblem | undefined> {
	const { data: begin } = await api().POST('/auth/passkey/begin');
	if (!begin) return 'other';
	let response;
	try {
		response = await startAuthentication({
			optionsJSON: begin.options as unknown as PublicKeyCredentialRequestOptionsJSON
		});
	} catch {
		return 'cancelled';
	}
	const { response: res } = await api().POST('/auth/passkey', {
		body: { ceremony: begin.ceremony, response: response as unknown as Record<string, unknown> }
	});
	return res.ok ? undefined : problemOf(res.status);
}

/** Creates a passkey on this device and stores it under name. */
export async function addPasskey(
	name: string,
	password: string
): Promise<PasskeyProblem | undefined> {
	const {
		data: begin,
		error,
		response: r1
	} = await api().POST('/me/passkeys/begin', {
		body: password ? { password } : {}
	});
	if (!begin) return problemOf(r1.status, error?.detail);
	let response;
	try {
		response = await startRegistration({
			optionsJSON: begin.options as unknown as PublicKeyCredentialCreationOptionsJSON
		});
	} catch {
		return 'cancelled';
	}
	const { response: r2 } = await api().POST('/me/passkeys', {
		body: {
			ceremony: begin.ceremony,
			name,
			response: response as unknown as Record<string, unknown>
		}
	});
	return r2.ok ? undefined : problemOf(r2.status);
}
