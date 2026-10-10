import { context, metrics, propagation } from '@opentelemetry/api';
import {
	ATTR_HTTP_REQUEST_METHOD,
	ATTR_HTTP_RESPONSE_STATUS_CODE,
	ATTR_HTTP_ROUTE
} from '@opentelemetry/semantic-conventions';
import { sequence, type Handle, type HandleFetch } from '@sveltejs/kit/hooks';
import { API_INTERNAL_URL } from '$app/env/private';
import { api } from '#lib/api/client.js';
import { prefixLocale } from '#lib/i18n.js';
import {
	cookieName,
	defineCustomServerStrategy,
	getTextDirection,
	locales
} from '#lib/paraglide/runtime.js';
import { paraglideMiddleware } from '#lib/paraglide/server.js';
import { parseTheme, themeAttribute, themeCookie } from '#lib/util/theme.js';

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
const apiInternalURL = () => API_INTERNAL_URL || 'http://localhost:8080';

const handleParaglide: Handle = ({ event, resolve }) =>
	// The request without the language prefix is not needed: reroute in
	// hooks.ts finds the route, and event.request is read-only (SvelteKit 3).
	paraglideMiddleware(event.request, ({ locale }) =>
		resolve(event, {
			transformPageChunk: ({ html }) =>
				html
					.replace('%paraglide.lang%', locale)
					.replace('%paraglide.dir%', getTextDirection(locale))
		})
	);

const handleTheme: Handle = ({ event, resolve }) => {
	event.locals.theme = parseTheme(event.cookies.get(themeCookie));
	return resolve(event, {
		transformPageChunk: ({ html }) =>
			html.replace('%alvyo.theme%', themeAttribute(event.locals.theme))
	});
};

const handleUser: Handle = async ({ event, resolve }) => {
	event.locals.user = null;
	if (event.cookies.get('alvyo_session')) {
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
	// No other site shows these pages in a frame (clickjacking).
	response.headers.set('Content-Security-Policy', "frame-ancestors 'none'");
	response.headers.set('X-Frame-Options', 'DENY');
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

// Request durations per route (/routes/[id], not the address), sent with
// OpenTelemetry when it is set up (instrumentation.server.ts).
const durations = metrics
	.getMeter('alvyo-web')
	.createHistogram('http.server.request.duration', { unit: 's' });

const handleMetrics: Handle = async ({ event, resolve }) => {
	const start = performance.now();
	const response = await resolve(event);
	durations.record((performance.now() - start) / 1000, {
		[ATTR_HTTP_REQUEST_METHOD]: event.request.method,
		[ATTR_HTTP_ROUTE]: event.route.id ?? 'unmatched',
		[ATTR_HTTP_RESPONSE_STATUS_CODE]: response.status
	});
	return response;
};

export const handle: Handle = sequence(
	handleMetrics,
	handleHeaders,
	handleCompression,
	handleParaglide,
	handleTheme,
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
		// The API's spans join the trace of this page.
		propagation.inject(context.active(), request.headers, {
			set: (headers, key, value) => headers.set(key, value)
		});
	}
	return fetch(request);
};
