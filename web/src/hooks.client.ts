import { prefixLocale } from '#lib/i18n.js';
import { defineCustomClientStrategy } from '#lib/paraglide/runtime.js';

defineCustomClientStrategy('custom-prefix', {
	getLocale: () => prefixLocale(location.pathname),
	setLocale: () => {} // the url strategy moves to the address
});
