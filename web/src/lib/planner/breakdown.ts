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
