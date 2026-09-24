/** Limits per item, as in the API. */
export const MAX_TAGS = 20;
export const MAX_TAG_LENGTH = 40;

/** Tags are compared without case. */
export function sameTag(a: string, b: string): boolean {
	return a.toLowerCase() === b.toLowerCase();
}

/** Whether an item passes the list's tag filter (none: everything does). */
export function hasTag(tags: string[], filter: string | null): boolean {
	return !filter || tags.some((t) => sameTag(t, filter));
}

/** Adds a typed tag: trimmed, spaces collapsed, not twice. */
export function addTag(tags: string[], typed: string): string[] {
	const t = typed.split(/\s+/).filter(Boolean).join(' ').slice(0, MAX_TAG_LENGTH);
	if (!t || tags.some((x) => sameTag(x, t)) || tags.length >= MAX_TAGS) return tags;
	return [...tags, t];
}
