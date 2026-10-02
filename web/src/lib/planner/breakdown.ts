/**
 * The shares of a breakdown to show, in the order of `keys`; none when
 * nothing but `unknown` is known (a grey bar says nothing).
 */
export function breakdownParts(
	values: Record<string, number>,
	keys: string[],
	unknown?: string
): { key: string; metres: number; share: number }[] {
	const total = keys.reduce((a, k) => a + (values[k] ?? 0), 0);
	if (total <= (unknown ? (values[unknown] ?? 0) : 0)) return [];
	return keys
		.filter((k) => (values[k] ?? 0) > 0)
		.map((k) => ({ key: k, metres: values[k], share: values[k] / total }));
}

/** A legend's lines: the `n` largest parts, the share of the rest as `other`. */
export function legendParts<P extends { share: number }>(
	parts: P[],
	n = 3
): { top: P[]; other: number } {
	const sorted = parts.toSorted((a, b) => b.share - a.share);
	return { top: sorted.slice(0, n), other: sorted.slice(n).reduce((a, p) => a + p.share, 0) };
}
