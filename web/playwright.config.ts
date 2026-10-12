import { defineConfig } from '@playwright/test';

// End-to-end tests run the real API and web app against the dev stack
// (`make infra-up`: PostGIS, Mailpit, GraphHopper, tile cache).
const API_PORT = 18080;
const WEB_PORT = 4173;

export default defineConfig({
	testMatch: '**/*.e2e.{ts,js}',
	// One browser at a time in CI: the runner draws the maps without a GPU, and
	// two at once left pages without an answer.
	workers: process.env.CI ? 1 : undefined,
	// German, like most tests expect; the language follows the browser.
	use: { baseURL: `http://localhost:${WEB_PORT}`, locale: 'de-CH' },
	projects: [
		{ name: 'chromium', use: { browserName: 'chromium' } },
		// Safari's engine, for what differs there.
		{ name: 'webkit', use: { browserName: 'webkit' }, testMatch: ['**/bugs.e2e.ts'] }
	],
	webServer: [
		{
			command:
				'cd .. && go build -o api/bin/alvyo ./api/cmd/alvyo && api/bin/alvyo migrate && api/bin/alvyo serve',
			url: `http://localhost:${API_PORT}/healthz`,
			reuseExistingServer: !process.env.CI,
			env: {
				ALVYO_DATABASE_URL:
					process.env.ALVYO_DATABASE_URL ??
					'postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable',
				ALVYO_LISTEN: `:${API_PORT}`,
				ALVYO_PUBLIC_URL: `http://localhost:${WEB_PORT}`,
				// every test signs up its own account from 127.0.0.1
				ALVYO_RELAXED_LIMITS: 'true',
				// the fake provider below
				ALVYO_OIDC_PROVIDERS: 'e2e',
				ALVYO_OIDC_E2E_NAME: 'Test-ID',
				ALVYO_OIDC_E2E_ISSUER: 'http://localhost:18090',
				ALVYO_OIDC_E2E_CLIENT_ID: 'alvyo',
				ALVYO_OIDC_E2E_CLIENT_SECRET: 'e2e-secret'
			}
		},
		{
			command: 'node tests/e2e/fake-idp.mjs',
			url: 'http://localhost:18090/.well-known/openid-configuration',
			reuseExistingServer: !process.env.CI
		},
		{
			command: 'bun run build && bun run preview',
			port: WEB_PORT,
			reuseExistingServer: !process.env.CI,
			env: {
				API_INTERNAL_URL: `http://localhost:${API_PORT}`,
				PUBLIC_CONTACT_EMAIL: 'hallo@alvyo.test',
				PUBLIC_OPERATOR_NAME: 'Alvyo Test',
				PUBLIC_OPERATOR_ADDRESS: 'Wanderweg 1, 3000 Bern'
			}
		}
	]
});
