import { expect, test } from './fixtures';

test('suggest several ways, change ways at a shared night, create the journey', async ({
	page
}) => {
	const id = `jsug${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Wegwahl',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	await page.goto('/journeys/plan');
	const panel = page.getByTestId('journey-plan-panel');
	await panel.getByLabel('Start suchen …').fill('Thun');
	await panel.getByRole('option', { name: /^Thun/ }).first().click();
	await panel.getByLabel('Ziel suchen …').fill('Zermatt');
	await panel
		.getByRole('option', { name: /^Zermatt/ })
		.first()
		.click();
	await expect(page.getByTestId('plan-point')).toHaveCount(2);

	await panel.getByLabel('Tage', { exact: true }).fill('5');
	await panel.getByRole('button', { name: 'Mehrere Wege vorschlagen' }).click();
	const ways = page.getByTestId('plan-way');
	await expect(ways.nth(1)).toBeVisible({ timeout: 60_000 });
	await expect(ways.first()).toHaveAttribute('aria-pressed', 'true');
	await expect(ways.first()).toContainText('Weg 1: direkt');
	await expect(ways.nth(1)).toContainText(/Weg 2: über /);

	// Another way: its days.
	const stages = page.getByTestId('plan-stage');
	await ways.nth(1).click();
	await expect(ways.nth(1)).toHaveAttribute('aria-pressed', 'true');
	await expect(stages.first()).toBeVisible();

	// Somewhere the ways sleep at the same place: go on along the other.
	const change = page.getByTestId('plan-switch').first();
	await expect(change).toBeVisible();
	await change.click();
	await expect(page.locator('[data-testid=plan-way][aria-pressed=true]')).toHaveCount(0);
	await expect(stages.first()).toContainText(/Weg \d/);
	// Put together: the nights stay where the ways have them.
	await expect(page.getByRole('button', { name: /^(Früher|Später): / })).toHaveCount(0);
	const n = await stages.count();

	await panel.getByLabel('Titel').fill('Thun – Zermatt');
	await panel.getByRole('button', { name: 'Etappentour erstellen' }).click();
	await expect(page.getByTestId('journey-title')).toHaveText('Thun – Zermatt');
	await expect(page.getByTestId('stage')).toHaveCount(n);
});

test('plan with hours per day from … to: the days follow', async ({ page }) => {
	const id = `jrng${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
	const signup = await page.request.post('/api/v1/auth/signup', {
		data: {
			email: `${id}@example.ch`,
			username: id,
			display_name: 'Stundenweise',
			password: 'sehr-geheim-123'
		}
	});
	expect(signup.status()).toBe(201);

	await page.goto('/journeys/plan');
	const panel = page.getByTestId('journey-plan-panel');
	await panel.getByLabel('Start suchen …').fill('Thun');
	await panel.getByRole('option', { name: /^Thun/ }).first().click();
	await panel.getByLabel('Ziel suchen …').fill('Zermatt');
	await panel
		.getByRole('option', { name: /^Zermatt/ })
		.first()
		.click();

	await panel.getByLabel('Stunden pro Tag', { exact: true }).check();
	// «Höchstens» belongs to the number of days.
	await expect(panel.getByText(/^Höchstens \(h pro Tag/)).toHaveCount(0);
	const min = panel.getByLabel('Mindestens Stunden pro Tag');
	const max = panel.getByLabel('Höchstens Stunden pro Tag');
	await min.fill('9');
	await max.fill('8');
	await expect(panel.getByRole('button', { name: 'Etappen vorschlagen' })).toBeDisabled();
	await min.fill('4');

	await panel.getByRole('button', { name: 'Etappen vorschlagen' }).click();
	const summary = page.getByTestId('plan-summary');
	await expect(summary).toBeVisible({ timeout: 60_000 });
	// About 30 h of hiking in days of at most 8 h: more than three.
	const days = Number((await summary.textContent())!.match(/(\d+) Tage/)![1]);
	expect(days).toBeGreaterThanOrEqual(4);
	await expect(page.getByTestId('plan-stage')).toHaveCount(days);
});
