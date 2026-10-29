import type { Person } from '#lib/api/client.js';
import { m } from '#lib/paraglide/messages.js';

/** A person's name: the account's, else (for the owner) the address invited. */
export function personName(p: Person): string {
	return p.display_name || p.username || p.email || m.people_invited();
}

/** The names of those who come along on a stage. */
export function stagePeople(people: Person[], stageId: string): string[] {
	return people.filter((p) => p.stages.includes(stageId)).map(personName);
}

/** Up to two initials for a round avatar. */
export function initials(name: string): string {
	return name
		.split(/\s+/)
		.filter(Boolean)
		.slice(0, 2)
		.map((w) => w[0].toUpperCase())
		.join('');
}
