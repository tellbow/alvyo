import { describe, expect, it } from 'vitest';
import { planQuery, readPlanQuery } from './query';

describe('planner query', () => {
	it('carries start, destination and profile there and back', () => {
		const q = planQuery({ at: [7.6912345, 46.4567891], name: 'Gitschenen' }, [7.7, 46.5], 'alpine');
		expect(q).toBe(
			'from=7.69123%2C46.45679&to=7.70000%2C46.50000&profile=alpine&from_name=Gitschenen'
		);
		expect(readPlanQuery(new URLSearchParams(q))).toEqual({
			profile: 'alpine',
			anchors: [
				{ lon: 7.69123, lat: 46.45679, name: 'Gitschenen' },
				{ lon: 7.7, lat: 46.5 }
			]
		});
	});

	it('needs both points; an unknown profile is hiking', () => {
		expect(readPlanQuery(new URLSearchParams('from=7.6,46.4'))).toBeUndefined();
		expect(readPlanQuery(new URLSearchParams('from=7.6,46.4&to=x,46.5'))).toBeUndefined();
		expect(
			readPlanQuery(new URLSearchParams('from=7.6,46.4&to=7.7,46.5&profile=car'))?.profile
		).toBe('hike');
	});
});
