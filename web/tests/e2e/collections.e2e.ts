import type { APIRequestContext } from '@playwright/test';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

/** A saved route near First, created through the API. */
async function createRoute(request: APIRequestContext, title: string, lon0: number) {
	const res = await request.post('/api/v1/routes', {
		data: { title, ...routeContent(lon0, 46.665) }
	});
	expect(res.status()).toBe(201);
	return (await res.json()).id as string;
}

test('collect routes and a journey, reorder and annotate them', async ({ page }) => {
	const id = `col${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Collector',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const first = await createRoute(page.request, 'Bachalpsee', 8.04);
	await createRoute(page.request, 'Faulhorn', 8.05);
	const journey = await page.request.post('/api/v1/journeys', {
		data: { title: 'Hardergrat bis Brienz', visibility: 'private' }
	});
	const journeyId = (await journey.json()).id as string;

	await page.goto('/collections');
	await page.getByLabel('Titel').fill('Sommer 2027');
	await page.getByRole('button', { name: 'Erstellen' }).click();
	await expect(page.getByTestId('collection-title')).toHaveValue('Sommer 2027');
	const collectionUrl = page.url();

	// Add from the route and journey pages.
	for (const path of [`/routes/${first}`, `/journeys/${journeyId}`]) {
		await page.goto(path);
		const select = page.getByTestId('add-to-collection');
		await expect(select.locator('option', { hasText: 'Sommer 2027' })).toHaveCount(1);
		await select.selectOption({ label: 'Sommer 2027' });
		await expect(page.getByRole('status')).toHaveText('Hinzugefügt zu «Sommer 2027»');
	}
	// Adding twice is refused politely.
	await page.goto(`/routes/${first}`);
	await page.getByTestId('add-to-collection').selectOption({ label: 'Sommer 2027' });
	await expect(page.getByRole('status')).toHaveText('Schon in «Sommer 2027»');

	await page.goto(collectionUrl);
	const items = page.getByTestId('collection-item');
	await expect(items).toHaveCount(2);
	await expect(items.nth(0)).toContainText('Bachalpsee');
	await expect(items.nth(1)).toContainText('Etappentour');

	// Move the journey up and note something on the route.
	const moved = page.waitForResponse((r) => r.request().method() === 'PATCH');
	await items.nth(1).getByRole('button', { name: 'Nach oben' }).click();
	expect((await moved).status()).toBe(200);
	await expect(items.nth(0)).toContainText('Hardergrat bis Brienz');
	const noted = page.waitForResponse((r) => r.request().method() === 'PATCH');
	await items.nth(1).getByLabel('Notiz').fill('Früh starten');
	await items.nth(1).getByLabel('Notiz').press('Tab');
	expect((await noted).status()).toBe(200);
	await page.reload();
	await expect(page.getByTestId('collection-item').nth(1).getByLabel('Notiz')).toHaveValue(
		'Früh starten'
	);
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /route-collection-line/);
	await page.waitForLoadState('networkidle');
	await page.screenshot({ path: 'test-results/collection.png' });

	await page.goto('/collections');
	await expect(page.getByTestId('collection-list')).toContainText('2 Einträge');
});

test('browsing a drop-down with the arrow keys acts only on Enter', async ({ page }) => {
	const id = `keys${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Keys',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	const route = await createRoute(page.request, 'Bachalpsee', 8.04);
	for (const title of ['Erste', 'Zweite']) {
		await page.request.post('/api/v1/collections', { data: { title } });
	}

	await page.goto(`/routes/${route}`);
	const select = page.getByTestId('add-to-collection');
	await expect(select.locator('option')).toHaveCount(3);
	await select.focus();
	// As on Windows and Linux: every arrow press changes the closed select
	// at once (Chromium on macOS opens a popup instead, so it is played here).
	const arrow = (label: string) =>
		select.evaluate((el: HTMLSelectElement, label) => {
			el.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
			el.value = [...el.options].find((o) => o.label === label)!.value;
			el.dispatchEvent(new Event('change', { bubbles: true }));
		}, label);
	await arrow('Erste');
	await arrow('Zweite');
	await page.waitForTimeout(300);
	await expect(page.getByRole('status')).toHaveCount(0);
	await select.press('Enter');
	await expect(page.getByRole('status')).toHaveText('Hinzugefügt zu «Zweite»');
	const list = await page.request.get('/api/v1/collections');
	const items = (await list.json()).collections.map((c: { title: string; items: number }) => [
		c.title,
		c.items
	]);
	expect(items.sort()).toEqual([
		['Erste', 0],
		['Zweite', 1]
	]);
});

test('add to a collection from the collection itself', async ({ page }) => {
	const id = `cadd${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Sammlerin',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	await createRoute(page.request, 'Bachalpsee', 8.04);
	await createRoute(page.request, 'Faulhorn', 8.05);

	await page.goto('/collections');
	await page.getByLabel('Titel').fill('Herbst');
	await page.getByRole('button', { name: 'Erstellen' }).click();
	await expect(page.getByTestId('collection-title')).toHaveValue('Herbst');

	const search = page.getByLabel('Route oder Etappentour hinzufügen …');
	await search.click();
	const found = page.getByTestId('collection-add-item');
	await expect(found).toHaveCount(2);
	await search.fill('faul');
	await expect(found).toHaveCount(1);
	await found.click();
	await expect(page.getByTestId('collection-items').locator('li')).toHaveCount(1);
	await expect(page.getByTestId('collection-items')).toContainText('Faulhorn');
	// What is in it is offered no more.
	await search.fill('');
	await expect(found).toHaveCount(1);
	await expect(found).toContainText('Bachalpsee');
});
