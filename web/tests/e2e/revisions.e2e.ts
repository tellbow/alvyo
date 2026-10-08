import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

test('an earlier version of a route is shown and restored', async ({ page }) => {
	const id = `rev${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await signUp(page.request, {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Planer',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(200);
	// 150 m, then saved again as 300 m.
	const created = await page.request.post('/api/v1/routes', {
		data: { title: 'Gratweg', visibility: 'private', ...routeContent(8.04, 46.665, 4) }
	});
	const { id: routeId } = await created.json();
	const { profile, anchors, legs } = routeContent(8.04, 46.665, 8);
	const saved = await page.request.patch(`/api/v1/routes/${routeId}`, {
		data: { profile, anchors, legs },
		headers: { 'If-Match': '"1"' }
	});
	expect(saved.status()).toBe(200);

	await page.goto(`/routes/${routeId}`);
	await expect(page.getByTestId('stat-distance')).toHaveText(/^3\d\d\sm$/);
	const versions = page.getByTestId('revisions');
	await page.getByTestId('route-menu').click();
	await versions.getByText('Versionen').click();
	await expect(versions.getByRole('listitem')).toHaveCount(1);
	await expect(versions.getByRole('listitem')).toContainText(`· ${id} · 1`);
	await versions.getByRole('link').click();

	await expect(page.getByTestId('revision')).toContainText(
		`Du siehst die Version vom ${new Intl.DateTimeFormat('de-CH', { dateStyle: 'medium', timeZone: 'Europe/Zurich' }).format(new Date())}`
	);
	await expect(page.getByTestId('stat-distance')).toHaveText(/^1\d\d\sm$/);
	await page.getByRole('button', { name: 'Wiederherstellen' }).click();

	await expect(page).toHaveURL(new RegExp(`/routes/${routeId}$`));
	await expect(page.getByTestId('revision')).toHaveCount(0);
	await expect(page.getByTestId('stat-distance')).toHaveText(/^1\d\d\sm$/);
	await page.getByTestId('route-menu').click();
	await versions.getByText('Versionen').click();
	await expect(versions.getByRole('listitem')).toHaveCount(2); // the 300 m line too
});
