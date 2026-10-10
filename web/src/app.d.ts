// See https://svelte.dev/docs/kit/types#app.d.ts
import type { Me } from '#lib/api/client.js';
import type { Theme } from '#lib/util/theme.js';

declare global {
	namespace App {
		interface Locals {
			user: Me | null;
			theme: Theme;
		}
		interface PageData {
			user: Me | null;
		}
	}
}

export {};
