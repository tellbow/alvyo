import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { linkFromMail, mailMatching } from './mailpit';

test('share a hike with a contact, who follows it by the link', async ({ page, browser }) => {
	const id = `live${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const email = `${id}@example.ch`;
	await page.request.post('/api/v1/auth/signup', {
		data: { email, username: id, display_name: 'Lena Live', password: 'sehr-geheim-123' }
	});
	const token = new URL(await linkFromMail(email, '/verify-email')).searchParams.get('token');
	await page.request.post('/api/v1/auth/verify-email', { data: { token } });

	// The contact is added in the account.
	const friend = `friend-${id}@example.ch`;
	await page.goto('/account');
	await page.getByLabel('Name', { exact: true }).fill('Freundin');
	await page.getByLabel('E-Mail', { exact: true }).fill(friend);
	await page.getByRole('button', { name: 'Hinzufügen', exact: true }).click();
	await expect(page.getByTestId('contacts')).toContainText('Freundin');

	// The app starts the hike and sends positions (here through the API).
	const created = await page.request.post('/api/v1/routes', {
		data: { title: 'Gratweg', ...routeContent(8.04, 46.665, 20) }
	});
	const route = (await created.json()).id as string;
	const contacts = await (await page.request.get('/api/v1/me/contacts')).json();
	const started = await page.request.post('/api/v1/live', {
		data: {
			title: 'Gratweg',
			route_id: route,
			contact_ids: [contacts.contacts[0].id],
			expected_end: new Date(Date.now() + 4 * 3600_000).toISOString()
		}
	});
	expect(started.status()).toBe(201);
	const share = await started.json();
	await page.request.post(`/api/v1/live/${share.id}/positions`, {
		data: { points: [{ lon: 8.045, lat: 46.665, t: new Date().toISOString() }] }
	});

	// The contact opens the link from the e-mail, without an account.
	const [link] = await mailMatching(friend, /https?:\/\/\S+\/live\/[\w-]+/);
	const guest = await browser.newContext();
	const view = await guest.newPage();
	await view.goto(link);
	const panel = view.getByTestId('live-panel');
	await expect(panel).toContainText('Lena Live ist unterwegs');
	await expect(panel).toContainText('Gratweg');
	await expect(view.getByTestId('live-status')).toContainText('Geplantes Ende');
	await expect(view.getByTestId('live-last')).toContainText('Letzter Standort');
	await expect(panel).toContainText('46.66500, 8.04500');
	await expect(view.getByTestId('live-position')).toBeVisible();

	await page.request.post(`/api/v1/live/${share.id}/end`);
	await view.reload();
	await expect(view.getByTestId('live-status')).toContainText('Wanderung beendet');
	await view.goto('/live/not-a-token');
	await expect(view.getByTestId('live-gone')).toBeVisible();
	await guest.close();
});
