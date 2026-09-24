import { prefixLocale } from '$lib/i18n';
import { defineCustomClientStrategy } from '$lib/paraglide/runtime';

defineCustomClientStrategy('custom-prefix', {
	getLocale: () => prefixLocale(location.pathname),
	setLocale: () => {} // the url strategy moves to the address
});
