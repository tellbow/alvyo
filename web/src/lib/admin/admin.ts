import type { components } from '#lib/api/schema.js';

export type AdminUser = components['schemas']['User'];
export type AdminItem = components['schemas']['Item'];
export type LogEntry = components['schemas']['LogEntry'];

const dateTime = new Intl.DateTimeFormat('de-CH', {
	dateStyle: 'medium',
	timeStyle: 'short',
	timeZone: 'Europe/Zurich'
});

/** A time as the admin portal shows it (German only). */
export const when = (t: string) => dateTime.format(new Date(t));

/** What a refused action means, in plain German. */
export function refused(status: number): string {
	switch (status) {
		case 403:
			return 'Nicht erlaubt: Moderator:innen und Admins sperrt man nicht, Rollen ändern nur Admins.';
		case 409:
			return 'Nichts zu ändern, oder seither wieder geändert: zuerst die spätere Änderung rückgängig machen.';
		case 422:
			return 'Die eigene Rolle änderst du nicht selbst.';
		default:
			return 'Das ging nicht. Bitte nochmals versuchen.';
	}
}
