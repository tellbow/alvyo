import { expect, test } from './fixtures';
import { linkFromMail, mailMatching } from './mailpit';

test('invite a friend to plan a journey along, and a newcomer by e-mail', async ({
	page,
	browser
}) => {
	const suffix = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const owner = `own${suffix}`;
	const friend = `fri${suffix}`;
	const signup = async (request: typeof page.request, name: string) => {
		const res = await request.post('/api/v1/auth/signup', {
			data: {
				email: `${name}@example.ch`,
				username: name,
				display_name: name,
				password: 'sehr-geheim-123'
			}
		});
		expect(res.status()).toBe(201);
	};

	// The owner (verified) with a journey of one stage.
	await signup(page.request, owner);
	const token = new URL(
		await linkFromMail(`${owner}@example.ch`, '/verify-email')
	).searchParams.get('token');
	expect((await page.request.post('/api/v1/auth/verify-email', { data: { token } })).status()).toBe(
		204
	);
	const created = await page.request.post('/api/v1/journeys', {
		data: { title: 'Gemeinsam', visibility: 'private' }
	});
	const { id } = await created.json();
	await page.request.post(`/api/v1/journeys/${id}/stages`, { data: {} });

	const friendContext = await browser.newContext();
	const friendPage = await friendContext.newPage();
	await signup(friendPage.request, friend);

	// Invite the friend by username as editor.
	await page.goto(`/journeys/${id}`);
	await page.getByTestId('tab-share').click();
	const panel = page.getByTestId('share-panel');
	await panel.getByLabel('Benutzername oder E-Mail-Adresse').fill(friend);
	await panel.getByLabel('Rolle').selectOption('editor');
	await panel.getByRole('button', { name: 'Einladen' }).click();
	await expect(panel.getByTestId('grant')).toContainText(`@${friend}`);

	// The friend finds it under "shared with me" and plans along, without settings.
	await friendPage.goto('/journeys');
	await friendPage.getByTestId('shared-journeys').getByRole('link', { name: 'Gemeinsam' }).click();
	await expect(friendPage.getByTestId('journey-title')).toHaveText('Gemeinsam');
	await expect(friendPage.getByText(`Gehört ${owner} – du planst mit.`)).toBeVisible();
	await expect(friendPage.getByTestId('tab-share')).toHaveCount(0);
	const saved = friendPage.waitForResponse((r) => r.request().method() === 'PATCH');
	await friendPage.getByTestId('stage').first().getByLabel('Titel').fill('Tag 1');
	await friendPage.getByTestId('stage').first().getByLabel('Titel').press('Tab');
	expect((await saved).status()).toBe(200);
	await friendContext.close();

	// A newcomer invited by e-mail gets a link that leads to the login first.
	const newcomer = `new${suffix}@example.ch`;
	await panel.getByLabel('Benutzername oder E-Mail-Adresse').fill(newcomer);
	await panel.getByRole('button', { name: 'Einladen' }).click();
	await expect(panel.getByTestId('grant').filter({ hasText: newcomer })).toContainText(
		'eingeladen'
	);
	const [link] = await mailMatching(newcomer, new RegExp(`https?://\\S+/journeys/${id}`));
	const anon = await browser.newContext();
	const anonPage = await anon.newPage();
	await anonPage.goto(new URL(link).pathname);
	await expect(anonPage).toHaveURL(new RegExp(`/login\\?redirect=%2Fjourneys%2F${id}$`));
	await anon.close();
});
