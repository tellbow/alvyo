import { describe, expect, it } from 'vitest';
import { POI_KINDS } from './places';
import { POI_ICONS } from './poiIcons';

describe('POI_ICONS', () => {
	it('has an icon and a colour of its own for every kind', () => {
		expect(Object.keys(POI_ICONS).sort()).toEqual([...POI_KINDS].sort());
		const colours = POI_KINDS.map((k) => POI_ICONS[k].color);
		expect(new Set(colours).size).toBe(colours.length);
		for (const k of POI_KINDS) expect(POI_ICONS[k].path).toMatch(/^M[\d. MLCZ]+$/);
	});
});
