import { defineEnvVars } from '@sveltejs/kit/env';

// Unset, they are empty: the API is then on localhost (hooks.server.ts),
// and no operator or contact on the about page. The operator (name and
// postal address) is who answers for the site under data protection law.
export const variables = defineEnvVars({
	API_INTERNAL_URL: { schema: (input) => input ?? '' },
	// The admin portal: its API (the admin listener) and, in production, its
	// own host on the internal ingress; unset, /admin is served here.
	ADMIN_API_INTERNAL_URL: { schema: (input) => input ?? '' },
	ADMIN_URL: { schema: (input) => input ?? '' },
	// Grafana, linked from the admin portal's «System»; unset, no link.
	PUBLIC_GRAFANA_URL: { public: true, schema: (input) => input ?? '' },
	PUBLIC_CONTACT_EMAIL: { public: true, schema: (input) => input ?? '' },
	PUBLIC_OPERATOR_NAME: { public: true, schema: (input) => input ?? '' },
	PUBLIC_OPERATOR_ADDRESS: { public: true, schema: (input) => input ?? '' }
});
