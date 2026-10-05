// Google Analytics (the tag in app.html, on alvyo.tellbow.ch only): page
// views without what gives access (share tokens, invitation and live
// location links, password resets) and without the titles of one's tours;
// cookies only once the visitor agreed (Consent Mode, banner).

type Gtag = (...args: unknown[]) => void;
type Analytics = { gtag?: Gtag; alvyoAnalytics?: boolean };

const KEY = 'alvyo_analytics';
export type Consent = 'granted' | 'denied';

/** Whether Google Analytics runs on this page (the site, not development or tests). */
export function analyticsActive(): boolean {
	return typeof window !== 'undefined' && !!(window as Analytics).alvyoAnalytics;
}

function gtag(...args: unknown[]) {
	(window as Analytics).gtag?.(...args);
}

/** The visitor's choice, if made. */
export function readConsent(): Consent | undefined {
	try {
		const v = localStorage.getItem(KEY);
		return v === 'granted' || v === 'denied' ? v : undefined;
	} catch {
		return undefined;
	}
}

/** Remembers the choice and tells Google. */
export function setConsent(c: Consent) {
	try {
		localStorage.setItem(KEY, c);
	} catch {
		// private mode: asked again next time
	}
	gtag('consent', 'update', { analytics_storage: c });
}

/**
 * The address as analytics sees it: no query (share tokens, password
 * resets, e-mail confirmations) or fragment, and the token of live location
 * and invitation links masked.
 */
export function analyticsUrl(url: URL): string {
	const path = url.pathname.replace(/\/(live|friends\/invite)\/[^/]+/, '/$1/-');
	return url.origin + path;
}

/** A page view: the address without secrets, the route's pattern as title. */
export function pageView(url: URL, routeId: string | null) {
	gtag('set', { page_location: analyticsUrl(url), page_title: routeId ?? '' });
	gtag('event', 'page_view');
}
