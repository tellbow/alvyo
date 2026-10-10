import { toJpeg } from 'html-to-image';
import { liveMaps } from '#lib/map/registry.js';

/**
 * The page as a JPEG data URL, without the bug report's own button. A map's
 * canvas keeps no picture between frames: each map is drawn once more and
 * laid over its canvas as an image while the page is taken.
 */
export async function pageScreenshot(): Promise<string | undefined> {
	const covers: HTMLElement[] = [];
	for (const map of liveMaps) {
		try {
			map.redraw();
			const canvas = map.getCanvas();
			const img = document.createElement('img');
			img.src = canvas.toDataURL('image/png'); // keeps what has no tiles transparent
			img.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none';
			canvas.parentElement?.append(img);
			covers.push(img);
		} catch {
			// a map without a picture: the rest still helps
		}
	}
	const options = {
		quality: 0.8,
		pixelRatio: Math.min(devicePixelRatio, 1.5),
		backgroundColor: getComputedStyle(document.body).backgroundColor,
		filter: (n: Node) => !(n instanceof HTMLElement && n.dataset.bugReport !== undefined),
		// Our fonts and images come from here; others would taint the page.
		skipFonts: false
	};
	try {
		// Safari leaves the maps' pictures out of the first rendering of a
		// page: that one is thrown away.
		await toJpeg(document.body, options);
		return await toJpeg(document.body, options);
	} catch {
		return undefined;
	} finally {
		covers.forEach((c) => c.remove());
	}
}
