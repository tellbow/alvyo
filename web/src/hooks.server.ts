import type { Handle, HandleFetch } from '@sveltejs/kit';
import { sequence } from '@sveltejs/kit/hooks';
import { env } from '$env/dynamic/private';
import { api } from '$lib/api/client';
import { prefixLocale } from '$lib/i18n';
import {
	cookieName,
	defineCustomServerStrategy,
	getTextDirection,
	locales
} from '$lib/paraglide/runtime';
import { paraglideMiddleware } from '$lib/paraglide/server';

// Paraglide asks custom strategies before all others on the server; the
// cookie must still win, as in the browser, or the two disagree.
defineCustomServerStrategy('custom-prefix', {
	getLocale: (request) => {
		if (!request) return undefined;
		const cookie = request.headers
			.get('cookie')
			?.match(new RegExp(`(?:^|;\\s*)${cookieName}=([^;]*)`));
		if (cookie && (locales as readonly string[]).includes(cookie[1])) return undefined;
		return prefixLocale(new URL(request.url).pathname);
	}
});

/** Where the Go API is reachable from this server (not from browsers). */
const apiInternalURL = () => env.API_INTERNAL_URL || 'http://localhost:8080';

const handleParaglide: Handle = ({ event, resolve }) =>
	paraglideMiddleware(event.request, ({ request, locale }) => {
		event.request = request;

		return resolve(event, {
			transformPageChunk: ({ html }) =>
				html
					.replace('%paraglide.lang%', locale)
					.replace('%paraglide.dir%', getTextDirection(locale))
		});
	});

const handleUser: Handle = async ({ event, resolve }) => {
	event.locals.user = null;
	if (event.cookies.get('odysgeh_session')) {
		const { data } = await api(event.fetch, event.url.origin).GET('/me');
		event.locals.user = data ?? null;
	}
	// openapi-fetch reads these headers of API responses during SSR.
	const serialized = new Set(['content-length', 'content-type', 'etag']);
	return resolve(event, { filterSerializedResponseHeaders: (name) => serialized.has(name) });
};

/** Set here rather than in a proxy, so they apply behind any ingress. */
const handleHeaders: Handle = async ({ event, resolve }) => {
	const response = await resolve(event);
	response.headers.set('X-Content-Type-Options', 'nosniff');
	response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
	response.headers.set('Permissions-Policy', 'geolocation=(self), camera=(), microphone=()');
	return response;
};

/** Page HTML, page data and the sitemap as gzip: journeys carry their stages' lines and
 * profile (100 KB and more). Static files come compressed already. */
const handleCompression: Handle = async ({ event, resolve }) => {
	const response = await resolve(event);
	const type = response.headers.get('content-type') ?? '';
	if (
		!response.body ||
		response.status !== 200 ||
		response.headers.has('content-encoding') ||
		!/^(text\/html|application\/json|application\/xml)/.test(type) ||
		!/\bgzip\b/.test(event.request.headers.get('accept-encoding') ?? '')
	) {
		return response;
	}
	const headers = new Headers(response.headers);
	headers.set('content-encoding', 'gzip');
	headers.append('vary', 'Accept-Encoding');
	headers.delete('content-length');
	return new Response(response.body.pipeThrough(new CompressionStream('gzip')), {
		status: response.status,
		statusText: response.statusText,
		headers
	});
};

export const handle: Handle = sequence(
	handleHeaders,
	handleCompression,
	handleParaglide,
	handleUser
);

/**
 * Server-side requests to /api/* go straight to the Go API. SvelteKit does not
 * forward cookies to other hosts, so the session cookie is copied explicitly.
 */
export const handleFetch: HandleFetch = async ({ event, request, fetch }) => {
	const url = new URL(request.url);
	if (url.origin === event.url.origin && url.pathname.startsWith('/api/')) {
		request = new Request(apiInternalURL() + url.pathname + url.search, request);
		const cookie = event.request.headers.get('cookie');
		if (cookie) request.headers.set('cookie', cookie);
	}
	return fetch(request);
};
