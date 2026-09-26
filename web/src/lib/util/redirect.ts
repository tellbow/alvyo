/** A same-site path to continue to after login; anything else goes home. */
export function safeRedirect(target: string | null): string {
	if (!target?.startsWith('/')) return '/';
	// Parsed as a browser does: "/\evil.example" is another site too.
	const base = 'http://alvyo.invalid';
	return new URL(target, base).origin === base ? target : '/';
}
