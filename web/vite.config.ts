import { paraglideVitePlugin } from '@inlang/paraglide-js';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vitest/config';
import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';

// The browser talks to the API and tile cache through the same origin; in
// production Caddy does this routing.
const proxy = {
	'/api': process.env.API_INTERNAL_URL || 'http://localhost:8080',
	'/tiles': process.env.TILES_URL || 'http://localhost:8081'
};

export default defineConfig({
	server: { proxy },
	preview: { proxy },
	plugins: [
		tailwindcss(),
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: adapter()
		}),

		paraglideVitePlugin({
			project: './project.inlang',
			outdir: './src/lib/paraglide',
			emitTsDeclarations: true,
			// A choice in the language menu (cookie) wins, then the address
			// (/en/…, /fr/…, /it/…: one per language for search engines), then
			// the browser's languages; German, without prefix, otherwise.
			// custom-prefix is defined in hooks.server.ts and hooks.client.ts:
			// the url strategy alone would read every unprefixed address as
			// German.
			strategy: ['cookie', 'custom-prefix', 'preferredLanguage', 'url', 'baseLocale']
		})
	],
	test: {
		expect: { requireAssertions: true },
		projects: [
			{
				extends: './vite.config.ts',
				test: {
					name: 'server',
					environment: 'node',
					include: ['src/**/*.{test,spec}.{js,ts}'],
					exclude: ['src/**/*.svelte.{test,spec}.{js,ts}']
				}
			}
		]
	}
});
