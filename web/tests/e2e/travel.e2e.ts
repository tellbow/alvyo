import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('from home to the start of a journey by public transport, chosen once and kept', async ({
	page
}) => {
	const id = `home${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Pendler',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	// A home, found by the place search in the account.
	await page.goto('/account');
	await page.getByRole('combobox', { name: 'Adresse suchen …' }).fill('Sargans');
	await page.getByRole('listbox').getByRole('option').first().click();
	await expect(page.getByTestId('home-address')).toBeVisible();
	await page.getByTestId('home-name').fill('Zuhause');
	await page.getByTestId('home-add').click();
	await expect(page.getByTestId('homes')).toContainText('Zuhause');

	const created = await page.request.post('/api/v1/journeys', {
		data: { title: 'Nach Weisstannen', visibility: 'private' }
	});
	const journeyId = (await created.json()).id as string;
	const api = `/api/v1/journeys/${journeyId}`;
	const one = await (await page.request.post(`${api}/stages`, { data: {} })).json();
	await page.request.post(`${api}/stages/${one.stage_list[0].id}/route`, {
		data: routeContent(9.34116, 46.9892)
	});

	// The journey planner is stubbed: tests must not spend the OJP quota.
	const asked: URL[] = [];
	await page.route('**/api/v1/connections?**', async (route) => {
		asked.push(new URL(route.request().url()));
		await route.fulfill({
			json: {
				trips: [
					{
						start: '2027-07-05T04:02:00Z',
						end: '2027-07-05T05:10:00Z',
						transfers: 1,
						legs: [
							{
								kind: 'walk',
								from: 'Zuhause',
								to: 'Sargans',
								duration_min: 6,
								track: [
									[9.44, 47.04],
									[9.445, 47.045]
								]
							},
							{
								kind: 'ride',
								mode: 'bus',
								line: 'B 432',
								from: 'Sargans, Bahnhof',
								to: 'Weisstannen, Oberdorf',
								departure: '2027-07-05T04:10:00Z',
								arrival: '2027-07-05T05:10:00Z',
								track: [
									[9.445, 47.045],
									[9.34116, 46.9892]
								]
							}
						]
					}
				]
			}
		});
	});

	await page.goto(`/journeys/${journeyId}`);
	const to = page.getByTestId('travel-to');
	await to.getByTestId('travel-to-home').selectOption({ label: 'Zuhause' });
	await to.getByTestId('travel-to-time').fill('06:00');
	await to.getByTestId('travel-to-time').dispatchEvent('change');
	await expect(to.getByTestId('trip')).toContainText('06:02 → 07:10'); // Swiss summer time
	await expect(to.getByTestId('trip')).toContainText('B 432');
	// First at the default time, then at the one chosen.
	await expect.poll(() => asked.at(-1)?.searchParams.get('time')).toBe('06:00');
	const last = asked.at(-1)!;
	expect(last.searchParams.get('from')).toMatch(/^9\.\d+,47\.\d+$/);
	expect(last.searchParams.get('from_name')).toBe('Zuhause');
	expect(last.searchParams.get('lines')).toBe('true');

	// Kept with the journey, for this user only; the GPX has only the stage.
	await page.reload();
	await expect(page.getByTestId('travel-to-home')).toHaveValue(/.+/);
	await expect(page.getByTestId('travel-to-time')).toHaveValue('06:00');
	const gpx = await (await page.request.get(`${api}/gpx`)).body();
	expect(gpx.includes(Buffer.from('B 432'))).toBe(false);
});

test('to a route and back from anywhere, on a day chosen, and on its sheet', async ({ page }) => {
	const id = `anyw${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Unterwegs',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Weisstannental', ...routeContent(9.34116, 46.9892) }
	});
	const route = (await res.json()).id as string;

	// The journey planner is stubbed: tests must not spend the OJP quota.
	const asked: URL[] = [];
	await page.route('**/api/v1/connections?**', async (r) => {
		asked.push(new URL(r.request().url()));
		await r.fulfill({
			json: {
				trips: [
					{
						start: '2027-07-05T04:10:00Z',
						end: '2027-07-05T05:10:00Z',
						transfers: 0,
						legs: [
							{
								kind: 'ride',
								mode: 'bus',
								line: 'B 432',
								from: 'Sargans, Bahnhof',
								to: 'Weisstannen, Oberdorf',
								departure: '2027-07-05T04:10:00Z',
								arrival: '2027-07-05T05:10:00Z'
							}
						]
					}
				]
			}
		});
	});

	// No home saved: from a place found by the search.
	await page.goto(`/routes/${route}`);
	const to = page.getByTestId('travel-to');
	await to.getByTestId('travel-to-home').selectOption({ label: 'Anderer Ort …' });
	await to.getByRole('combobox', { name: 'Ort, Haltestelle oder Adresse' }).fill('Sargans');
	await to.getByRole('listbox').getByRole('option').first().click();
	await expect(to.getByTestId('travel-to-place')).toContainText('Sargans');
	await expect(to.getByTestId('trip')).toContainText('06:10 → 07:10');
	expect(asked.at(-1)?.searchParams.get('from_name')).toContain('Sargans');

	// Another day: its connections.
	await page.getByTestId('travel-day').fill('2027-07-05');
	await page.getByTestId('travel-day').dispatchEvent('change');
	await expect.poll(() => asked.at(-1)?.searchParams.get('date')).toBe('2027-07-05');

	// Kept for the route; on its sheet with the day of the sheet.
	await page.reload();
	await expect(page.getByTestId('travel-to-place')).toContainText('Sargans');
	await page.goto(`/routes/${route}/sheet`);
	await page.getByLabel('Tag').fill('2027-07-06');
	const trips = page.getByTestId('sheet-trips');
	await expect(trips).toContainText(/Anreise: Sargans.* → Start/);
	await expect(trips.getByTestId('sheet-trip')).toContainText('B 432');
	await expect.poll(() => asked.at(-1)?.searchParams.get('date')).toBe('2027-07-06');
});
