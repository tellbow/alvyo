import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('a route through a wildlife rest area says so, with its rules', async ({ page }) => {
	const id = `wrz${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Ruhe',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);
	// 8.01 to 8.04 at 46.665: through the Grindelwald rest area Spilmatten-Reetihorn
	// (geo.admin's identify service, as in production).
	const res = await page.request.post('/api/v1/routes', {
		data: { title: 'Durch die Ruhezone', ...routeContent(8.01, 46.665, 60) }
	});
	expect(res.status()).toBe(201);
	const route = (await res.json()).id as string;

	// Icons the map draws itself are there when first needed.
	const missing: string[] = [];
	page.on('console', (m) => {
		if (m.type() === 'warning' && /could not be loaded/.test(m.text())) missing.push(m.text());
	});
	await page.goto(`/routes/${route}`);
	// A line with how many, the list in a popup.
	const areas = page.getByTestId('protected-areas');
	await expect(areas).toBeVisible({ timeout: 20_000 });
	await expect(page.getByTestId('protected-area')).toBeHidden();
	await areas.getByTestId('protected-areas-open').click();
	const popup = page.getByRole('dialog', { name: 'Schutzgebiete auf dem Weg' });
	const area = popup.getByTestId('protected-area').filter({ hasText: 'Spilmatten-Reetihorn' });
	await expect(area).toContainText('Wildruhezone · verbindlich');
	await expect(area).toContainText('Zutrittsverbot · 1. Dez. bis 20. Apr.');
	await expect(area.getByRole('link', { name: /Mehr dazu/ })).toHaveAttribute(
		'href',
		/^https:\/\//
	);
	await page.screenshot({ path: 'test-results/areas-popup.png' });
	await page.keyboard.press('Escape');
	await expect(popup).toBeHidden();

	// Along the way: the Reeti (2757 m) right at the start, from OpenStreetMap.
	await page.getByTestId('tab-along').click();
	await expect(page.getByTestId('poi').first()).toHaveText(/^\d+\sm\s*Reeti · Gipfel · 2757\sm$/);
	// Also on the map, with their icons.
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\broute-pois\b/);
	// Pointing at a row rings its point on the map.
	await expect(page.getByTestId('map')).toHaveAttribute('data-layers', /\broute-pois-highlight\b/);
	await page.getByTestId('poi').first().hover();
	await page.waitForTimeout(500);
	expect(missing).toEqual([]);
	await page.screenshot({ path: 'test-results/route-pois.png' });

	// The weather: MeteoSwiss's symbol for today; a date beyond the forecast
	// has what is usual in its month.
	await page.getByTestId('tab-overview').click();
	const weather = page.getByTestId('weather');
	await expect(weather.getByTestId('weather-icon').first()).toBeVisible({ timeout: 20_000 });
	const later = new Date(Date.now() + 60 * 864e5).toISOString().slice(0, 10);
	await weather.getByTestId('weather-date').fill(later);
	await expect(weather.getByTestId('weather-place').first()).toContainText(
		/Üblich im \p{L}+: -?\d+–-?\d+\s°C/u
	);
	await expect(weather.getByTestId('weather-climate-source')).toContainText(
		'Klimanormwerte 1991–2020'
	);
	await weather.getByTestId('weather-place').first().scrollIntoViewIfNeeded();
	await page.screenshot({ path: 'test-results/weather-climate.png' });

	// The same line in the planner is checked as it is drawn.
	await page.goto(`/plan/${route}`);
	await page.getByTestId('protected-areas-open').click({ timeout: 20_000 });
	await expect(
		page.getByTestId('protected-area').filter({ hasText: 'Spilmatten-Reetihorn' })
	).toBeVisible();
});
