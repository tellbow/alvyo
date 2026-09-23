import { m } from '$lib/paraglide/messages';
import type { BaseMapId, OverlayId } from './styles';

export const baseLabel: Record<BaseMapId, () => string> = {
	landeskarte: m.map_base_landeskarte,
	landeskarte_grau: m.map_base_landeskarte_grau,
	luftbild: m.map_base_luftbild,
	basemap: m.map_base_basemap
};

export const overlayLabel: Record<OverlayId, () => string> = {
	wanderwege: m.map_ovl_wanderwege,
	wanderland: m.map_ovl_wanderland,
	hangneigung: m.map_ovl_hangneigung,
	relief: m.map_ovl_relief
};
