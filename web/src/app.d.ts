// See https://svelte.dev/docs/kit/types#app.d.ts
import type { Me } from '$lib/api/client';
import type { Theme } from '$lib/util/theme';

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
