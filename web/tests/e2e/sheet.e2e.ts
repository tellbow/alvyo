import { readFileSync } from 'node:fs';
import { expect, test } from './fixtures';
import { leg, routeContent } from './legs';

// Sargans – Weisstannen, every eighth point: through a town with many
// fountains and restaurants along the way.
const sargansWeisstannen: number[][] = JSON.parse(
	readFileSync(new URL('files/sargans-weisstannen.json', import.meta.url), 'utf8')
);

async function signup(page: import('@playwright/test').Page, prefix: string) {
	const id = `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const res = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Blatt',
			password: 'sehr-geheim-123'
		}
	});
	expect(res.status()).toBe(201);
}

test('a route on a sheet to print: map, profile and numbers, light on paper', async ({
	page,
	baseURL
}) => {
	await signup(page, 'sheet');
	await page.context().addCookies([{ name: 'alvyo_theme', value: 'dark', url: baseURL! }]);
	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Zum Mitnehmen', ...routeContent(8.01, 46.665, 20) }
	});
	const route = (await res.json()).id as string;

	await page.goto(`/routes/${route}`);
	await page.getByTestId('route-menu').click();
	await page.getByTestId('sheet-link').click();
	await expect(page).toHaveURL(`/routes/${route}/sheet`);
	await expect(page.getByTestId('sheet-title')).toHaveText('Zum Mitnehmen');
	await expect(page.getByTestId('sheet-map')).toBeVisible({ timeout: 20_000 });
	await expect(page.getByTestId('sheet-map')).toHaveAttribute('src', /^data:image\/png/);
	await expect(page.getByTestId('elevation-profile')).toBeVisible();
	await expect(page.getByTestId('route-stats')).toBeVisible();
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');

	// On paper: no menu, no buttons.
	await page.emulateMedia({ media: 'print' });
	await expect(page.locator('header').first()).toBeHidden();
	await expect(page.getByRole('button', { name: 'Drucken oder als PDF sichern' })).toBeHidden();
	await page.emulateMedia({ media: 'screen' });

	// Back on the route, the chosen theme again.
	await page.getByRole('link', { name: '← Zurück' }).click();
	await expect(page).toHaveURL(`/routes/${route}`);
	await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
});

test('a stage on a sheet: its day, places and the transfer by public transport', async ({
	page
}) => {
	await signup(page, 'stsheet');
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
	const patched = await page.request.patch(`${api}/stages/${s2}`, {
		headers: { 'If-Match': `"${two.stage_list[1].version}"` },
		data: { transfer_before: 'pt', planned_date: '2027-07-05', accommodation: 'Hotel Segnes' }
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
							}
						]
					}
				]
			}
		});
	});

	await page.goto(`/journeys/${journeyId}`);
	await page.getByTestId('stage').nth(1).getByTestId('stage-sheet').click();
	await expect(page).toHaveURL(`/journeys/${journeyId}/stages/${s2}/sheet`);
	await expect(page.getByTestId('sheet-title')).toContainText('Elm');
	await expect(page.getByText('Etappe 2 · Via Alpina Ost')).toBeVisible();
	await expect(page.getByTestId('sheet-day')).toHaveText('Montag, 5. Juli 2027');
	await expect(page.getByTestId('sheet-places')).toContainText('Hotel Segnes');
	const trips = page.getByTestId('sheet-trips');
	await expect(trips).toContainText('Weisstannen, Oberdorf → Elm, Station');
	const trip = trips.getByTestId('sheet-trip');
	await expect(trip).toContainText('07:12 → 09:20 · 2 Umst.');
	await expect(trip).toContainText(
		'07:12 B 432 Weisstannen, Oberdorf → Sargans, Bahnhof (Gl./Kante E)'
	);
	expect(asked?.searchParams.get('date')).toBe('2027-07-05');
	await expect(page.getByTestId('sheet-map')).toBeVisible({ timeout: 20_000 });

	// Another day: the connections of that day.
	await page.getByLabel('Tag').fill('2027-07-06');
	await expect.poll(() => asked?.searchParams.get('date')).toBe('2027-07-06');
});

test('a real stage through a town on one A4 page', async ({ page, browserName }) => {
	test.skip(browserName !== 'chromium', 'only Chromium prints to PDF');
	await signup(page, 'onepage');
	const journeyId = (
		await (
			await page.request.post('/api/v1/journeys', {
				data: { title: 'Via Alpina', visibility: 'private' }
			})
		).json()
	).id as string;
	const api = `/api/v1/journeys/${journeyId}`;
	await page.request.post(`${api}/stages`, { data: {} });
	const two = await (await page.request.post(`${api}/stages`, { data: {} })).json();
	const [s1, s2] = two.stage_list.map((s: { id: string }) => s.id);
	const line = sargansWeisstannen;
	// The stage before ends at the station where this one starts.
	await page.request.post(`${api}/stages/${s1}/route`, {
		data: routeContent(line[0][0] - 0.002, line[0][1])
	});
	const end = line[line.length - 1];
	await page.request.post(`${api}/stages/${s2}/route`, {
		data: {
			profile: 'hike',
			anchors: [
				{ lon: line[0][0], lat: line[0][1] },
				{ lon: end[0], lat: end[1] }
			],
			legs: [leg(line)]
		}
	});
	const tomorrow = new Date(Date.now() + 864e5).toISOString().slice(0, 10);
	const patched = await page.request.patch(`${api}/stages/${s2}`, {
		headers: { 'If-Match': `"${two.stage_list[1].version}"` },
		data: {
			title: 'Sargans – Weisstannen',
			transfer_before: 'pt',
			planned_date: tomorrow,
			accommodation: 'Gasthaus Alpenhof, Weisstannen',
			notes: 'Proviant in Sargans kaufen.'
		}
	});
	expect(patched.status()).toBe(200);
	const trip = (h: number) => ({
		start: `${tomorrow}T0${h}:05:00Z`,
		end: `${tomorrow}T0${h + 1}:40:00Z`,
		transfers: 1,
		legs: [
			['S12', 'Buchs SG', 'Sargans', 'E'],
			['B 441', 'Sargans, Bahnhof', 'Weisstannen, Oberdorf', 'C']
		].map(([line, from, to, platform], i) => ({
			kind: 'ride',
			mode: i ? 'bus' : 'train',
			line,
			from,
			to,
			departure: `${tomorrow}T0${h}:${i ? 45 : '05'}:00Z`,
			arrival: `${tomorrow}T0${h}:${i ? 59 : 40}:00Z`,
			platform
		}))
	});
	await page.route('**/api/v1/connections?**', (route) =>
		route.fulfill({ json: { trips: [trip(5), trip(6), trip(7)] } })
	);

	await page.goto(`/journeys/${journeyId}/stages/${s2}/sheet`);
	await expect(page.getByTestId('sheet-map')).toBeVisible({ timeout: 20_000 });
	await expect(page.getByTestId('sheet-trips')).toBeVisible();
	await expect(page.getByTestId('pois')).toBeVisible();
	const pdf = await page.pdf({ preferCSSPageSize: true, printBackground: true });
	expect(pdf.toString('latin1').match(/\/Type\s*\/Page[^s]/g)).toHaveLength(1);
});
