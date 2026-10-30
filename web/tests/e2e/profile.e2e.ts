import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

// A friend sees on a profile what they may open and what the user hiked,
// also of others, planned or hiked, and the collections (feedback issues 58,
// 65 and 68).
test('a profile: hikes for friends, planned or hiked, collections', async ({ page, browser }) => {
	const s = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const people = { anna: `anna${s}`, bea: `bea${s}`, carl: `carl${s}` };
	const contexts = { bea: await browser.newContext(), carl: await browser.newContext() };
	const requests = { anna: page.request, bea: contexts.bea.request, carl: contexts.carl.request };
	for (const [who, username] of Object.entries(people)) {
		const res = await signUp(requests[who as keyof typeof people], {
			data: {
				email: `${username}@example.ch`,
				username,
				display_name: who[0].toUpperCase() + who.slice(1),
				password: 'sehr-geheim-123'
			}
		});
		expect(res.status()).toBe(200);
	}
	const create = async (who: keyof typeof people, title: string, visibility: string, lon: number) =>
		(
			await (
				await requests[who].post('/api/v1/routes', {
					data: { title, visibility, ...routeContent(lon, 46.665) }
				})
			).json()
		).id as string;
	const open = await create('anna', 'Offen', 'public', 8.04);
	await create('anna', 'Geheim', 'private', 8.05);
	const carls = await create('carl', 'Carls Gipfel', 'public', 8.06);
	await page.request.put(`/api/v1/routes/${carls}/done`, { data: { done_on: '2026-08-01' } });
	const collection = await (
		await page.request.post('/api/v1/collections', {
			data: { title: 'Gipfel', visibility: 'public' }
		})
	).json();
	for (const id of [open, carls]) {
		await page.request.post(`/api/v1/collections/${collection.id}/items`, {
			data: { route_id: id }
		});
	}
	await page.request.put(`/api/v1/users/${people.bea}/friend`);
	await requests.bea.put(`/api/v1/users/${people.anna}/friend`);
	await requests.bea.put(`/api/v1/routes/${open}/done`, { data: { done_on: '2026-08-02' } });

	const bea = await contexts.bea.newPage();
	await bea.goto(`/u/${people.anna}`);
	const routes = bea.getByTestId('profile-routes');
	await expect(routes).toContainText('Offen');
	await expect(routes).toContainText('Carls Gipfel');
	await expect(routes).not.toContainText('Geheim');
	await expect(routes.getByTestId('byline')).toHaveText(
		`✓ Gewandert am 1.8.2026 · von ${people.carl}`
	);
	await expect(bea.getByTestId('profile-counts')).toContainText('Gewandert');
	await bea.screenshot({ path: 'test-results/profile-friend.png', fullPage: true });

	await bea.getByTestId('done-filter').getByText('Gewandert').click();
	await expect(routes).not.toContainText('Offen');
	await expect(routes).toContainText('Carls Gipfel');
	await bea.getByRole('tab', { name: 'Sammlungen' }).click();
	await expect(bea.getByTestId('profile-collections')).toContainText('Gipfel');

	// A stranger sees no hikes.
	await page.context().clearCookies();
	await page.goto(`/u/${people.anna}`);
	await expect(page.getByTestId('profile-routes')).not.toContainText('Carls Gipfel');
	await expect(page.getByTestId('done-filter')).toHaveCount(0);

	// The collection, by what the viewer hiked.
	await bea.goto(`/collections/${collection.id}`);
	const items = bea.getByTestId('collection-items');
	await expect(items.getByTestId('collection-item')).toHaveCount(2);
	await bea.getByTestId('done-filter').getByText('Geplant').click();
	await expect(items.getByTestId('collection-item')).toHaveCount(1);
	await expect(items).toContainText('Carls Gipfel');
	await bea.screenshot({ path: 'test-results/collection-filter.png', fullPage: true });
	await contexts.bea.close();
	await contexts.carl.close();
});
