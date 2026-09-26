import type { Place } from '$lib/api/client';
import { m } from '$lib/paraglide/messages';

export function placeLabel(kind: Place['kind']): string {
	switch (kind) {
		case 'pt_stop':
			return m.place_kind_pt_stop();
		case 'hut':
			return m.place_kind_hut();
		case 'hotel':
			return m.place_kind_hotel();
		case 'campsite':
			return m.place_kind_campsite();
	}
}

/** What kind of place it is, as specific as the data allows ("Bus", "Hütte" …). */
export function placeDetail(p: Pick<Place, 'kind' | 'detail'>): string {
	if (p.kind === 'pt_stop') return p.detail || placeLabel(p.kind); // BAV modes, German
	if (p.detail === 'wilderness_hut') return m.place_wilderness_hut();
	return placeLabel(p.kind);
}
