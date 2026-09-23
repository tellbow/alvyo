// See https://svelte.dev/docs/kit/types#app.d.ts
import type { Me } from '$lib/api/client';

declare global {
	namespace App {
		interface Locals {
			user: Me | null;
		}
		interface PageData {
			user: Me | null;
		}
	}
}

export {};
