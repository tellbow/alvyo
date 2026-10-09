<script lang="ts">
	import type { Official } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { getLocale } from '$lib/paraglide/runtime';
	import { officialLabel, schweizMobilUrl } from './official';

	// Instead of «von wanderland»: which official route, where it is
	// described, and whose data it is (open data that requires the source).
	let { official }: { official: Official } = $props();
</script>

<p class="text-sm text-stone-500" data-testid="official">
	{officialLabel(official)} ·
	<!-- An outside page: resolve() does not apply. -->
	<!-- eslint-disable svelte/no-navigation-without-resolve -->
	<a
		href={schweizMobilUrl(official.number, getLocale())}
		target="_blank"
		rel="noopener noreferrer"
		class="text-accent-ink hover:underline">{m.official_link()} ↗</a
	>
	<!-- eslint-enable svelte/no-navigation-without-resolve -->
</p>
<p class="text-xs text-stone-500">{m.official_source()}</p>
