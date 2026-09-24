import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('connections for a public transport transfer between stages', async ({ page }) => {
	const id = `pt${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pendlerin',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	// Stage 1 ends at Weisstannen, Oberdorf; stage 2 starts at Elm, Station.
	const created = await page.request.post('/api/v1/journeys', {
		data: { title: 'Via Alpina Ost', visibility: 'private' }
	});
	const journeyId = (await created.json()).id as string;
	const api = `/api/v1/journeys/${journeyId}`;
	await page.request.post(`${api}/stages`, { data: {} });
	const two = await (await page.request.post(`${api}/stages`, { data: {} })).json();
	const [s1, s2] = two.stage_list.map((s: { id: string }) => s.id);
	await page.request.post(`${api}/stages/${s1}/route`, { data: routeContent(9.34116, 46.9892) });
	await page.request.post(`${api}/stages/${s2}/route`, { data: routeContent(9.17306, 46.92227) });
	// Adding a route leaves the stage's version as it was.
	const patched = await page.request.patch(`${api}/stages/${s2}`, {
		headers: { 'If-Match': `"${two.stage_list[1].version}"` },
		data: { transfer_before: 'pt' }
	});
	expect(patched.status()).toBe(200);

	// The journey planner is stubbed: tests must not spend the OJP quota.
	let asked: URL | undefined;
	await page.route('**/api/v1/connections?**', async (route) => {
		asked = new URL(route.request().url());
		await route.fulfill({
			json: {
				trips: [
					{
						start: '2027-07-05T05:12:00Z',
						end: '2027-07-05T07:20:00Z',
						transfers: 2,
						legs: [
							{
								kind: 'ride',
								mode: 'bus',
								line: 'B 432',
								from: 'Weisstannen, Oberdorf',
								to: 'Sargans, Bahnhof',
								departure: '2027-07-05T05:12:00Z',
								arrival: '2027-07-05T05:48:00Z',
								platform: 'E'
							},
							{ kind: 'walk', from: 'Sargans, Bahnhof', to: 'Sargans', duration_min: 3 }
						]
					}
				]
			}
		});
	});

	await page.goto(`/journeys/${journeyId}`);
	const gap = page.getByTestId('gap');
	await expect(gap).toHaveAttribute('data-status', 'transfer');
	await expect(gap.getByTestId('sbb-transfer')).toBeVisible();
	await gap.getByRole('button', { name: 'Verbindungen anzeigen' }).click();
	const trip = gap.getByTestId('trip');
	await expect(trip).toContainText('07:12 → 09:20'); // Swiss summer time
	await expect(trip).toContainText('B 432');
	await expect(trip).toContainText('3 min zu Fuss');
	expect(asked?.searchParams.get('from')).toBe('8509965');
	expect(asked?.searchParams.get('to')).toBe('8503277');
});
