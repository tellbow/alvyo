<script lang="ts">
	import { m } from '#lib/paraglide/messages.js';
	import { intlLocale } from '#lib/util/locale.js';

	/** Set while geo.admin does not answer: the time of the hints shown. */
	let { asOf }: { asOf?: string } = $props();

	const date = $derived(
		asOf &&
			new Intl.DateTimeFormat(intlLocale(), {
				dateStyle: 'medium',
				timeZone: 'Europe/Zurich'
			}).format(new Date(asOf))
	);
</script>

{#if date}
	<p class="text-xs text-stone-500" data-testid="areas-as-of">{m.areas_as_of({ date })}</p>
{/if}
