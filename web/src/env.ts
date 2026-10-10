import { defineEnvVars } from '@sveltejs/kit/env';

// Unset, they are empty: the API is then on localhost (hooks.server.ts),
// and no contact on the about page.
export const variables = defineEnvVars({
	API_INTERNAL_URL: { schema: (input) => input ?? '' },
	PUBLIC_CONTACT_EMAIL: { public: true, schema: (input) => input ?? '' }
});
