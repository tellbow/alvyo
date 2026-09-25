import { describe, expect, it } from 'vitest';
import { api } from './client';

describe('api', () => {
	it('answers 503 when the server cannot be reached', async () => {
		const offline = (() => Promise.reject(new TypeError('Failed to fetch'))) as typeof fetch;
		const { data, error, response } = await api(offline, 'https://alvyo.test').GET('/me');
		expect(data).toBeUndefined();
		expect(response.status).toBe(503);
		expect(error?.detail).toBe('no connection');
	});

	it('leaves cancelled requests cancelled', async () => {
		const aborted = (() =>
			Promise.reject(new DOMException('aborted', 'AbortError'))) as typeof fetch;
		await expect(api(aborted, 'https://alvyo.test').GET('/me')).rejects.toThrow('aborted');
	});
});
