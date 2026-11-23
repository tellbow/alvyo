<script lang="ts">
	import { resolve } from '$app/paths';
	import { cantonName } from '#lib/cantons.js';
	import { getLocale } from '#lib/paraglide/runtime.js';
	import { m } from '#lib/paraglide/messages.js';

	/** The cantons a route or journey crosses, linked to their pages. */
	let { codes }: { codes: string[] } = $props();
</script>

{#if codes.length > 0}
	<p class="text-sm text-stone-500" data-testid="cantons">
		{m.canton_region()}:
		{#each codes as code, i (code)}{#if i > 0},
			{/if}<a
				href={resolve('/cantons/[code]', { code: code.toLowerCase() })}
				class="hover:underline">{cantonName(code, getLocale())}</a
			>{/each}
	</p>
{/if}
