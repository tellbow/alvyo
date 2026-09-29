import { POI_KINDS, type PoiKind } from './places';

const STORAGE_KEY = 'alvyo-poi-kinds';

function read(): PoiKind[] {
	try {
		const v = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? 'null');
		if (Array.isArray(v)) return POI_KINDS.filter((k) => v.includes(k));
	} catch {
		// no storage (server, blocked): all kinds
	}
	return [...POI_KINDS];
}

/** The kinds along the way the maps show, shared by all maps and remembered in the browser. */
export const poiShown = $state({ kinds: typeof window === 'undefined' ? [...POI_KINDS] : read() });

export function togglePoiKind(kind: PoiKind) {
	poiShown.kinds = poiShown.kinds.includes(kind)
		? poiShown.kinds.filter((k) => k !== kind)
		: POI_KINDS.filter((k) => k === kind || poiShown.kinds.includes(k));
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(poiShown.kinds));
	} catch {
		// not remembered, still switched
	}
}
