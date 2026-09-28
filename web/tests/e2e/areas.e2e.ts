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

	await page.goto(`/routes/${route}`);
	const areas = page.getByTestId('protected-areas');
	await expect(areas).toBeVisible({ timeout: 20_000 });
	const area = areas.getByTestId('protected-area').filter({ hasText: 'Spilmatten-Reetihorn' });
	await expect(area).toContainText('Wildruhezone · verbindlich');
	await expect(area).toContainText('Zutrittsverbot · 1. Dez. bis 20. Apr.');
	await expect(area.getByRole('link', { name: /Mehr dazu/ })).toHaveAttribute(
		'href',
		/^https:\/\//
	);

	// Along the way: the Reeti (2757 m) right at the start, from OpenStreetMap.
	await expect(page.getByTestId('poi').first()).toHaveText(/^\d+\sm\s*Reeti · Gipfel · 2757\sm$/);

	// The same line in the planner is checked as it is drawn.
	await page.goto(`/plan/${route}`);
	await expect(
		page.getByTestId('protected-area').filter({ hasText: 'Spilmatten-Reetihorn' })
	).toBeVisible({
		timeout: 20_000
	});
});
