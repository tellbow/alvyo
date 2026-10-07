import { describe, expect, it } from 'vitest';
import pkg from '../../package.json';

describe('package.json', () => {
	// adapter-node bundles devDependencies into build/ but leaves dependencies
	// as imports, and the image runs without node_modules: a dependency
	// breaks every page that imports it (/login with the passkeys, once
	// every page with html-to-image).
	it('has no dependencies, only devDependencies', () => {
		expect(Object.keys((pkg as { dependencies?: object }).dependencies ?? {})).toEqual([]);
	});
});
