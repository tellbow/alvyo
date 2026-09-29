import icons from './poi-icons.json';
import type { PoiKind } from './places';

/** Each kind along the way: a white shape (24 × 24) on a disc of its colour; the app draws the same. */
export const POI_ICONS = icons as Record<
	PoiKind,
	{ color: string; evenodd: boolean; path: string }
>;

/** Draws a kind's icon for the map, `px` wide, at the screen's pixel ratio. */
export function drawPoiIcon(kind: PoiKind, px: number, ratio: number): ImageData | undefined {
	const icon = POI_ICONS[kind];
	const size = Math.round(px * ratio);
	const ctx = Object.assign(document.createElement('canvas'), {
		width: size,
		height: size
	}).getContext('2d');
	if (!ctx) return undefined;
	const s = size / 24;
	ctx.fillStyle = icon.color;
	ctx.strokeStyle = '#fff';
	ctx.lineWidth = 1.5 * s;
	ctx.beginPath();
	ctx.arc(size / 2, size / 2, size / 2 - ctx.lineWidth / 2, 0, 2 * Math.PI);
	ctx.fill();
	ctx.stroke();
	// The shape at 70 %, centred.
	ctx.setTransform(0.7 * s, 0, 0, 0.7 * s, 3.6 * s, 3.6 * s);
	ctx.fillStyle = '#fff';
	ctx.fill(new Path2D(icon.path), icon.evenodd ? 'evenodd' : 'nonzero');
	return ctx.getImageData(0, 0, size, size);
}
