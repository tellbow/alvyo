import type { Page } from '@playwright/test';
import { expect, test } from './fixtures';

async function signup(page: Page, name: string) {
	const id = `${name}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const res = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: name,
			password: 'sehr-geheim-123'
		}
	});
	expect(res.status()).toBe(201);
}

/** A GPX track of about 2.2 km (n points 76 m apart) heading east from lon/lat. */
function track(name: string, lon: number, lat: number, n = 30) {
	const pts = Array.from(
		{ length: n },
		(_, i) => `<trkpt lat="${lat}" lon="${(lon + i * 0.001).toFixed(4)}"/>`
	);
	return `<trk><name>${name}</name><trkseg>${pts.join('')}</trkseg></trk>`;
}

test('a GPX file with several tracks becomes a journey', async ({ page }) => {
	await signup(page, 'importer');
	await page.goto('/routes');
	await page.getByRole('link', { name: 'Importieren' }).click();
	await expect(page).toHaveURL(/\/import$/);

	const gpx = `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">${track('Tag 1', 9.3, 46.99)}${track('Tag 2', 9.33, 46.99)}${track('Mailand', 9.19, 45.46)}</gpx>`;
	// The input takes files once the page has hydrated.
	const input = page.getByTestId('file-import').getByLabel('Datei hochladen');
	await expect(input).toBeEnabled();
	await input.setInputFiles({
		name: 'durchquerung.gpx',
		mimeType: 'application/gpx+xml',
		buffer: Buffer.from(gpx)
	});

	const tracks = page.getByTestId('import-tracks');
	await expect(tracks.getByRole('listitem')).toHaveCount(3);
	await expect(tracks.getByRole('listitem').nth(2)).toContainText('ausserhalb CH/FL');

	const submit = page.getByTestId('file-import').getByRole('button', { name: 'Importieren' });
	await expect(submit).toBeDisabled(); // the mode must be chosen
	await page.getByLabel('Als Etappentour – eine Etappe pro Track').check();
	await page.getByTestId('file-import').getByLabel('Titel').fill('Test-Durchquerung');
	await submit.click();

	await expect(page.getByTestId('import-skipped')).toContainText(
		'Mailand: liegt nicht ganz in der Schweiz oder in Liechtenstein'
	);
	await page.getByRole('link', { name: 'Etappentour öffnen' }).click();
	await expect(page.getByRole('heading', { name: 'Test-Durchquerung' })).toBeVisible();
	await expect(page.getByTestId('stage')).toHaveCount(3);
});

test('Komoot tours are picked and imported in batches', async ({ page }) => {
	await signup(page, 'komooter');
	// Komoot itself is only reached by the API; the browser's API calls are
	// stubbed so the test needs neither Komoot nor an account there.
	await page.route('**/api/v1/imports/komoot/login', async (route) => {
		if (route.request().postDataJSON().password !== 'richtig') {
			return route.fulfill({ status: 422, json: { status: 422, title: 'Unprocessable Entity' } });
		}
		await route.fulfill({
			json: {
				session: 's1',
				total_pages: 1,
				tours: [
					{
						id: 1,
						type: 'tour_recorded',
						name: 'Faulhorn',
						date: '2026-08-01T07:00:00Z',
						sport: 'hike',
						distance: 10500
					},
					{
						id: 2,
						type: 'tour_planned',
						name: 'Navigli',
						date: '2026-07-01T07:00:00Z',
						sport: 'hike',
						distance: 4000
					},
					{
						id: 3,
						type: 'tour_recorded',
						name: 'Niesen',
						date: '2026-06-01T07:00:00Z',
						sport: 'hike',
						distance: 7000,
						imported_route_id: '0199a000-0000-7000-8000-000000000003'
					}
				]
			}
		});
	});
	let requested: number[] = [];
	await page.route('**/api/v1/imports/komoot', async (route) => {
		requested = route.request().postDataJSON().tour_ids;
		await route.fulfill({
			json: {
				routes: [{ id: '0199a000-0000-7000-8000-000000000001', title: 'Faulhorn', ref: '1' }],
				skipped: [{ name: 'Navigli', reason: 'outside' }]
			}
		});
	});

	await page.goto('/import');
	const komoot = page.getByTestId('komoot-import');
	await komoot.getByLabel('E-Mail bei Komoot').fill('hiker@example.ch');
	await komoot.getByLabel('Passwort bei Komoot').fill('falsch');
	await komoot.getByRole('button', { name: 'Bei Komoot anmelden' }).click();
	await expect(komoot.getByRole('alert')).toHaveText(
		'Komoot hat E-Mail oder Passwort nicht akzeptiert.'
	);
	await expect(komoot.getByLabel('Passwort bei Komoot')).toHaveValue('');

	await komoot.getByLabel('Passwort bei Komoot').fill('richtig');
	await komoot.getByRole('button', { name: 'Bei Komoot anmelden' }).click();
	const tours = komoot.getByTestId('komoot-tours');
	await expect(tours.getByRole('listitem')).toHaveCount(3);
	await expect(
		tours.getByRole('listitem').nth(2).getByRole('link', { name: 'importiert' })
	).toBeVisible();

	await komoot.getByRole('button', { name: 'Alle nicht importierten auswählen' }).click();
	await expect(komoot).toContainText('2 ausgewählt');
	await komoot.getByRole('button', { name: 'Importieren' }).click();

	await expect(komoot.getByTestId('import-result')).toContainText('Faulhorn');
	await expect(komoot.getByTestId('import-skipped')).toContainText('Navigli: liegt nicht ganz');
	expect(requested.sort()).toEqual([1, 2]);
	await expect(
		tours.getByRole('listitem').first().getByRole('link', { name: 'importiert' })
	).toBeVisible();
	await expect(komoot).toContainText('0 ausgewählt');
});

test('a GPX file becomes the route of a stage', async ({ page }) => {
	await signup(page, 'stager');
	const res = await page.request.post('/api/v1/journeys', { data: { title: 'Zwei Tage' } });
	const { id } = await res.json();
	for (const title of ['Tag 1', 'Tag 2']) {
		await page.request.post(`/api/v1/journeys/${id}/stages`, { data: { title } });
	}
	await page.goto(`/journeys/${id}`);
	const stage2 = page.getByTestId('stage').nth(1);
	await expect(stage2).toContainText('Noch keine Route');
	// Hydrated (the layout mounts last): a file set before is lost.
	await expect(page.getByLabel('Sprache')).toBeEnabled();

	const gpx = (n: number) => ({
		name: 'tag2.gpx',
		mimeType: 'application/gpx+xml',
		buffer: Buffer.from(
			`<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">${track('Tag 2', 9.33, 46.99, n)}</gpx>`
		)
	});
	await stage2.getByLabel('Datei importieren').setInputFiles(gpx(30));
	await expect(stage2).toContainText(/2\.\d km/);
	await expect(page.getByTestId('stage-marker')).toHaveCount(1);

	// A route is only replaced after asking.
	await stage2.getByRole('button', { name: 'Datei importieren' }).click();
	await expect(stage2.getByTestId('stage-import-replace')).toContainText(
		'wird durch die Datei ersetzt'
	);
	await stage2.getByLabel('Datei wählen').setInputFiles(gpx(10));
	await expect(stage2).toContainText(/\b[6-8]\d\d m/);
	await expect(stage2.getByTestId('stage-import-replace')).toHaveCount(0);
});

test('a recording of three days becomes a journey of three stages, after a preview', async ({
	page
}) => {
	await signup(page, 'recorder');
	// 30 points a day heading east, a minute apart, the nights in between.
	const days = ['2026-07-04', '2026-07-05', '2026-07-06'].map((date, d) =>
		Array.from(
			{ length: 30 },
			(_, i) =>
				`<trkpt lat="46.99" lon="${(9.3 + d * 0.03 + i * 0.001).toFixed(4)}"><time>${date}T08:${String(i).padStart(2, '0')}:00Z</time></trkpt>`
		).join('')
	);
	const gpx = `<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Drei Tage</name><trkseg>${days.join('')}</trkseg></trk></gpx>`;
	await page.goto('/import');
	const dialog = page.getByTestId('file-import');
	await expect(dialog.getByLabel('Datei hochladen')).toBeEnabled();
	await dialog.getByLabel('Datei hochladen').setInputFiles({
		name: 'drei-tage.gpx',
		mimeType: 'application/gpx+xml',
		buffer: Buffer.from(gpx)
	});
	await expect(dialog.getByTestId('import-tracks').getByRole('listitem')).toHaveCount(1);
	await dialog.getByLabel('Als Etappentour, in').check();
	await expect(dialog.getByLabel('Etappen', { exact: true })).toHaveValue('3');
	await expect(dialog).toContainText('Aufgezeichnet an 3 Tagen');

	// Nothing is created before the preview is accepted.
	await dialog.getByRole('button', { name: 'Etappen vorschlagen' }).click();
	const stages = dialog.getByTestId('import-stages').getByRole('listitem');
	await expect(stages).toHaveCount(3, { timeout: 30_000 });
	await expect(stages.nth(2).getByTestId('import-stage-end')).toContainText('bis zum Ziel');
	const journeys = await page.request.get('/api/v1/journeys');
	expect((await journeys.json()).journeys).toHaveLength(0);

	await dialog.getByRole('button', { name: 'Etappentour erstellen' }).click();
	await expect(page.getByTestId('journey-title')).toHaveText('Drei Tage');
	await expect(page.getByTestId('stage')).toHaveCount(3);
});
