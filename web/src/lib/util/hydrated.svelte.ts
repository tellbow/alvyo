import { onMount } from 'svelte';

/**
 * True once the component runs in the browser with its event handlers
 * attached. Submit buttons stay disabled until then: a form submitted before
 * hydration would be sent natively instead of through our handler.
 */
export class Hydrated {
	value = $state(false);

	constructor() {
		onMount(() => {
			this.value = true;
		});
	}
}
