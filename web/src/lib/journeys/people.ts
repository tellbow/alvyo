import type { Person } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';

/** A person's name: the account's, else (for the owner) the address invited. */
export function personName(p: Person): string {
	return p.display_name || p.username || p.email || m.people_invited();
}

/** The names of those who come along on a stage. */
export function stagePeople(people: Person[], stageId: string): string[] {
	return people.filter((p) => p.stages.includes(stageId)).map(personName);
}
