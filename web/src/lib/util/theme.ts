/**
 * Light or dark: after the system setting unless chosen. The choice is kept
 * in a cookie, so the server renders the page in it (no flash of the other).
 */
export const themes = ['system', 'light', 'dark'] as const;
export type Theme = (typeof themes)[number];

export const themeCookie = 'alvyo_theme';

export function parseTheme(v: string | null | undefined): Theme {
	return v === 'light' || v === 'dark' ? v : 'system';
}

/** The value of <html data-theme>; empty follows the system. */
export const themeAttribute = (t: Theme) => (t === 'system' ? '' : t);

export function setTheme(t: Theme) {
	document.cookie =
		t === 'system'
			? `${themeCookie}=; path=/; max-age=0; samesite=lax`
			: `${themeCookie}=${t}; path=/; max-age=31536000; samesite=lax`;
	document.documentElement.dataset.theme = themeAttribute(t);
}
