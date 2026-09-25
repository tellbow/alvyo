import { expect, test } from './fixtures';

test('plan a two-stage journey that continues where the previous stage ended', async ({
	page,
	context
}) => {
	await context.addInitScript(() => {
		localStorage.setItem(
			'alvyo.map',
			JSON.stringify({
				base: 'landeskarte',
				overlays: ['wanderwege'],
				center: [8.04, 46.665],
				zoom: 14
			})
		);
	});
	const id = `trip${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Tripper',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	await page.goto('/journeys');
	await page.getByLabel('Titel').fill('Rund um First');
	await page.getByRole('button', { name: 'Erstellen' }).click();
	await expect(page.getByTestId('journey-title')).toHaveText('Rund um First');
	const journeyUrl = page.url();

	const clickMap = async (dx: number, dy: number) => {
		const box = (await page.locator('canvas.maplibregl-canvas').boundingBox())!;
		await page.mouse.click(box.x + box.width / 2 + dx, box.y + box.height / 2 + dy);
	};
	const ready = async () => {
		await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /ovl-wanderwege/);
	};

	// Stage 1: planned from scratch.
	await page.getByRole('button', { name: 'Etappe hinzufügen' }).click();
	await expect(page).toHaveURL(/\/stages\/[0-9a-f-]{36}$/);
	await ready();
	await clickMap(-250, 80);
	await clickMap(0, -60);
	await expect(page.getByTestId('leg').first()).toHaveAttribute('data-state', 'ok', {
		timeout: 15_000
	});
	await page.getByRole('button', { name: 'Etappe speichern' }).click();
	await expect(page).toHaveURL(journeyUrl);
	await expect(page.getByTestId('stage-marker')).toHaveCount(1);

	// Stage 2 starts at the end of stage 1 automatically.
	await page.getByRole('button', { name: 'Etappe hinzufügen' }).click();
	await ready();
	await expect(page.getByTestId('anchor')).toHaveCount(1);
	await expect(page.getByTestId('ghost')).toHaveCount(1);
	await clickMap(250, 40);
	await expect(page.getByTestId('leg').first()).toHaveAttribute('data-state', 'ok', {
		timeout: 15_000
	});
	await page.getByRole('button', { name: 'Etappe speichern' }).click();
	await expect(page).toHaveURL(journeyUrl);
	await expect(page.getByTestId('stage-marker')).toHaveCount(2);
	await expect(page.getByTestId('gap')).toHaveCount(0); // stages connect

	// Progress, profile and download.
	await page.getByTestId('stage').first().getByLabel('Status').selectOption('done');
	await expect(page.getByTestId('journey-progress')).toHaveText('1 von 2 Etappen');
	await expect(page.getByTestId('elevation-profile')).toBeVisible();
	const zip = await page.request.get(
		journeyUrl.replace('/journeys/', '/api/v1/journeys/') + '/gpx'
	);
	expect(zip.status()).toBe(200);
	expect(zip.headers()['content-type']).toBe('application/zip');

	// Choose where stage 1 ends; a stop gets a timetable link.
	const first = page.getByTestId('stage').first();
	await first.getByTestId('stage-end').getByRole('button').click();
	await first.getByTestId('place-picker').getByLabel('Name suchen').fill('First (Grindelwald)');
	await first.getByRole('button', { name: /^First \(Grindelwald\)/ }).click();
	await expect(first.getByTestId('stage-end')).toContainText('First (Grindelwald)');
	await expect(first.getByTestId('stage-end')).not.toContainText('nächstgelegen');
	const sbb = new URL((await first.getByTestId('sbb-end').getAttribute('href'))!);
	expect(sbb.searchParams.get('von')).toBe('First (Grindelwald)');

	// Accommodation and notes are kept.
	await first.getByText('Unterkunft & Notizen').click();
	await first.getByLabel('Unterkunft').fill('Berggasthaus First');
	await first.getByLabel('Unterkunft').press('Tab');
	const saved = page.waitForResponse(
		(r) => r.request().method() === 'PATCH' && !!r.request().postData()?.includes('booked')
	);
	await first.getByLabel('Gebucht').check();
	expect((await saved).status()).toBe(200);
	await expect(page.getByTestId('stage').first().getByLabel('Gebucht')).toBeChecked();
	await page.reload();
	await expect(page.getByTestId('stage').first().getByLabel('Unterkunft')).toHaveValue(
		'Berggasthaus First'
	);
	await expect(page.getByTestId('stage').first().getByLabel('Gebucht')).toBeChecked();
	await page.screenshot({ path: 'test-results/journey.png' });

	// Delete stage 2.
	const second = page.getByTestId('stage').nth(1);
	await second.getByRole('button', { name: 'Etappe löschen' }).click();
	await second.getByRole('button', { name: 'Etappe samt Route löschen?' }).click();
	await expect(page.getByTestId('stage')).toHaveCount(1);
	await expect(page.getByTestId('stage-marker')).toHaveCount(1);
});

test('a stage changed by someone else meanwhile is not overwritten', async ({ page }) => {
	const id = `conf${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Two',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const created = await page.request.post('/api/v1/journeys', { data: { title: 'Zu zweit' } });
	const journeyId = (await created.json()).id as string;
	const added = await page.request.post(`/api/v1/journeys/${journeyId}/stages`, {
		data: { title: 'Tag 1' }
	});
	const stage = (await added.json()).stage_list[0];

	await page.goto(`/journeys/${journeyId}`);
	const card = page.getByTestId('stage').first();
	await expect(card.getByLabel('Titel')).toHaveValue('Tag 1');

	// Another editor renames the stage; this page still shows the old version.
	const other = await page.request.patch(`/api/v1/journeys/${journeyId}/stages/${stage.id}`, {
		headers: { 'If-Match': `"${stage.version}"` },
		data: { title: 'Tag 1 (von Bea)' }
	});
	expect(other.status()).toBe(200);

	await card.getByLabel('Titel').fill('Tag 1 (von mir)');
	await card.getByLabel('Titel').press('Tab');
	await expect(page.getByRole('alert')).toContainText(
		'Jemand hat diese Etappe inzwischen geändert'
	);
	await expect(card.getByLabel('Titel')).toHaveValue('Tag 1 (von Bea)');
});
