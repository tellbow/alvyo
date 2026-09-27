/** A route or journey that can go into a collection. */
export type Candidate = {
	kind: 'route' | 'journey';
	id: string;
	title: string;
	/** Set for what someone shared with the user. */
	owner?: string;
};

/**
 * The candidates whose title has all words of the query (any case), not in
 * the collection yet ([taken]: "kind:id"), at most [limit].
 */
export function candidates(
	all: Candidate[],
	taken: Set<string>,
	query: string,
	limit = 8
): Candidate[] {
	const words = query.toLowerCase().split(/\s+/).filter(Boolean);
	return all
		.filter(
			(c) =>
				!taken.has(`${c.kind}:${c.id}`) && words.every((w) => c.title.toLowerCase().includes(w))
		)
		.slice(0, limit);
}
