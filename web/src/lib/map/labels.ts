import { m } from '#lib/paraglide/messages.js';
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
	wildruhezonen: m.map_ovl_wildruhezonen,
	jagdbanngebiete: m.map_ovl_jagdbanngebiete,
	relief: m.map_ovl_relief,
	precip: m.map_ovl_precip,
	huts: m.map_ovl_huts,
	lodging: m.map_ovl_lodging,
	pois: m.map_ovl_pois
};
