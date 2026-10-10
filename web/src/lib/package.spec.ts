import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import pkg from '../../package.json';

describe('package.json', () => {
	// adapter-node bundles devDependencies into build/ but leaves dependencies
	// as imports: a dependency the image lacks breaks every page that imports
	// it (/login with the passkeys, once every page with html-to-image). The
	// one dependency is @opentelemetry/api, which SvelteKit imports itself.
	it('has only the dependencies the image installs', () => {
		expect(Object.keys((pkg as { dependencies?: object }).dependencies ?? {})).toEqual([
			'@opentelemetry/api'
		]);
		const dockerfile = readFileSync(new URL('../../Dockerfile', import.meta.url), 'utf8');
		expect(dockerfile).toContain('bun install --frozen-lockfile --production');
		expect(dockerfile).toContain('COPY --from=build /app/node_modules node_modules');
	});
});
