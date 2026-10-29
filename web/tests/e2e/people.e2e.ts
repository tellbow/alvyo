import { signUp } from './accounts';
import { expect, test } from './fixtures';

test('who comes along, on which stages, and reminders before the start', async ({
	page,
	browser
}) => {
	const suffix = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const owner = `own${suffix}`;
	const friend = `fri${suffix}`;
	const signup = async (request: typeof page.request, name: string) => {
		const res = await signUp(request, {
			data: {
				email: `${name}@example.ch`,
				username: name,
				display_name: `Name ${name}`,
				password: 'sehr-geheim-123'
			}
		});
		expect(res.status()).toBe(200);
	};

	// The owner (verified) with a journey of two stages, starting in 40 days.
	await signup(page.request, owner);
	const { id } = await (
		await page.request.post('/api/v1/journeys', {
			data: { title: 'Zu zweit', visibility: 'public' }
		})
	).json();
	await page.request.post(`/api/v1/journeys/${id}/stages`, { data: {} });
	const journey = await (
		await page.request.post(`/api/v1/journeys/${id}/stages`, { data: {} })
	).json();
	const first = journey.stage_list[0];
	const start = new Date(Date.now() + 40 * 864e5).toISOString().slice(0, 10);
	await page.request.patch(`/api/v1/journeys/${id}/stages/${first.id}`, {
		data: { planned_date: start },
		headers: { 'If-Match': `"${first.version}"` }
	});

	const friendContext = await browser.newContext();
	const friendPage = await friendContext.newPage();
	await signup(friendPage.request, friend);

	// The friend comes along, only on the second stage.
	// «Leute einladen» at the top opens the people tab (feedback issue 50).
	await page.goto(`/journeys/${id}`);
	await page.getByTestId('people-invite').click();
	await expect(page.getByTestId('people-who')).toBeFocused();
	const people = page.getByTestId('journey-people');
	await people.getByTestId('people-who').fill(friend);
	await people.getByTestId('people-add').click();
	const person = people.getByTestId('person');
	await expect(person).toContainText(`Name ${friend}`);
	await person.getByRole('button', { name: '1', exact: true }).click();
	await expect(person.getByRole('button', { name: '1', exact: true })).toHaveAttribute(
		'aria-pressed',
		'false'
	);
	await page.getByTestId('tab-stages').click();
	await expect(page.getByTestId('stage').nth(1).getByTestId('stage-people')).toHaveText(
		`Mit Name ${friend}`
	);
	await expect(page.getByTestId('stage').first().getByTestId('stage-people')).toHaveCount(0);
	await expect(page.getByTestId('people-row')).toContainText(`mit Name ${friend}`);
	await expect(page.getByTestId('tab-people')).toContainText('1');
	// All six tabs within the panel, none past its edge.
	const bar = (await page.getByRole('tablist').boundingBox())!;
	for (const tab of await page.getByRole('tab').all()) {
		const b = (await tab.boundingBox())!;
		expect(b.x + b.width).toBeLessThanOrEqual(bar.x + bar.width);
	}

	// Reminders: on, three to come; turned off, kept off.
	await page.getByTestId('tab-overview').click();
	const reminders = page.getByTestId('journey-reminders');
	await expect(reminders.getByTestId('reminders-on')).toBeChecked();
	await expect(reminders.getByRole('listitem')).toHaveCount(3);
	await reminders.getByTestId('reminders-on').uncheck();
	await page.reload();
	await page.getByTestId('tab-overview').click();
	await expect(page.getByTestId('journey-reminders').getByTestId('reminders-on')).not.toBeChecked();

	// The friend sees who comes along; a stranger on the public journey does not.
	await friendPage.goto(`/journeys/${id}`);
	await friendPage.getByTestId('tab-people').click();
	await expect(friendPage.getByTestId('journey-people').getByTestId('person')).toContainText(
		`Name ${friend}`
	);
	await expect(friendPage.getByTestId('people-who')).toHaveCount(0);
	await friendContext.close();
	const strangerContext = await browser.newContext();
	const stranger = await strangerContext.newPage();
	await signup(stranger.request, `str${suffix}`);
	await stranger.goto(`/journeys/${id}`);
	await expect(stranger.getByTestId('journey-title')).toHaveText('Zu zweit');
	await expect(stranger.getByTestId('journey-people')).toHaveCount(0);
	await strangerContext.close();
});
