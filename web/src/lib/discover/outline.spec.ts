import { describe, expect, it } from 'vitest';
import { outline } from './outline';

describe('outline', () => {
	it('fits the line into the box, north up', () => {
		// Due north: a vertical line through the middle.
		expect(
			outline(
				[
					[
						[8, 46],
						[8, 46.1]
					]
				],
				40,
				20,
				0
			)
		).toBe('M20 20L20 0');
	});

	it('draws each line as its own subpath', () => {
		const d = outline(
			[
				[
					[8, 46],
					[8.1, 46]
				],
				[
					[8.1, 46],
					[8.2, 46]
				]
			],
			40,
			20
		);
		expect(d.match(/M/g)).toHaveLength(2);
	});

	it('is empty without a line', () => {
		expect(outline([], 40, 20)).toBe('');
	});
});
