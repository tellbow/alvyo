/** A same-site path to continue to after login; anything else goes home. */
export function safeRedirect(target: string | null): string {
	return target && target.startsWith('/') && !target.startsWith('//') ? target : '/';
}
