import { execFileSync } from 'node:child_process';
import type { APIRequestContext } from '@playwright/test';
import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';
import { mailMatching } from './mailpit';

const suffix = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

/** Signs up and verifies an account in request's cookie jar. */
async function member(request: APIRequestContext, name: string, displayName: string) {
	const email = `${name}@example.ch`;
	const res = await signUp(request, {
		data: { email, username: name, display_name: displayName, password: 'sehr-geheim-123' }
	});
	expect(res.status()).toBe(200);
}

test('like, comment and follow; the owner hears about it by e-mail', async ({ page, browser }) => {
	const s = suffix();
	const owner = `own${s}`;
	const fan = `fan${s}`;
	await member(page.request, owner, 'Olga Owner');
	const created = await page.request.post('/api/v1/routes', {
		data: { title: `Höhenweg ${s}`, visibility: 'public', ...routeContent(8.04, 46.665) }
	});
	const { id } = await created.json();

	const fanContext = await browser.newContext();
	const fanPage = await fanContext.newPage();
	await member(fanPage.request, fan, 'Fritz Fan');

	await fanPage.goto(`/routes/${id}`);
	await fanPage.getByTestId('tab-photos').click();
	const social = fanPage.getByTestId('social');
	// «Merken» at the top and the count with the comments are the same like.
	await fanPage.getByTestId('route-like').click();
	await expect(fanPage.getByTestId('route-like')).toHaveText('♥ Merken');
	await expect(social.getByTestId('like')).toHaveText('♥ 1 Mal gemerkt');
	await social.getByLabel('Kommentar schreiben …').fill('Wunderbare Aussicht!');
	await social.getByRole('button', { name: 'Kommentieren' }).click();
	await expect(social.getByTestId('comment')).toContainText('Wunderbare Aussicht!');
	await mailMatching(`${owner}@example.ch`, /Fritz Fan \(@fan\w+\) hat deine Route/);

	// Follow the owner; their public routes appear in the fan's news.
	await fanPage.goto(`/u/${owner}`);
	await fanPage.getByRole('button', { name: 'Folgen' }).click();
	await expect(
		fanPage.getByTestId('profile-counts').getByText('Follower', { exact: true }).locator('..')
	).toContainText('1');
	await mailMatching(`${owner}@example.ch`, /Fritz Fan \(@fan\w+\) folgt dir jetzt/);
	await fanPage.getByRole('link', { name: 'Neuigkeiten' }).click();
	await expect(fanPage.getByTestId('feed')).toContainText(`Höhenweg ${s}`);

	// The owner sees the comment with a delete button and can switch comments off.
	await page.goto(`/routes/${id}`);
	await page.getByTestId('tab-photos').click();
	const own = page.getByTestId('social');
	await expect(own.getByTestId('comment')).toContainText('Wunderbare Aussicht!');
	await expect(own.getByRole('button', { name: 'Löschen' })).toBeVisible();
	await own.getByLabel('Kommentare erlauben').uncheck();
	await expect(own).toContainText('Kommentare sind ausgeschaltet.');
	await fanPage.goto(`/routes/${id}`);
	await fanPage.getByTestId('tab-photos').click();
	await expect(fanPage.getByTestId('social')).toContainText('Kommentare sind ausgeschaltet.');
	await expect(fanPage.getByTestId('comment')).toHaveCount(0);
	await fanContext.close();
});

test('a reported comment is removed from the moderation queue', async ({ page, browser }) => {
	const s = suffix();
	const owner = `own${s}`;
	const troll = `trl${s}`;
	const moderator = `mod${s}`;
	await member(page.request, owner, 'Olga Owner');
	const created = await page.request.post('/api/v1/routes', {
		data: { title: `Gratweg ${s}`, visibility: 'public', ...routeContent(8.05, 46.665) }
	});
	const { id } = await created.json();

	const trollContext = await browser.newContext();
	await member(trollContext.request, troll, 'Tom Troll');
	await trollContext.request.post(`/api/v1/routes/${id}/comments`, {
		data: { body: `Kauft billige Wanderschuhe ${s}` }
	});
	await trollContext.close();

	await page.goto(`/routes/${id}`);
	await page.getByTestId('tab-photos').click();
	const comment = page.getByTestId('comment').filter({ hasText: s });
	await comment.getByRole('button', { name: 'Melden' }).click();
	await page.getByTestId('report-form').getByRole('button', { name: 'Melden' }).click();
	await expect(comment).toContainText('Danke, wir schauen es uns an.');

	// A moderator (role set with the CLI, as in production) removes it.
	const modContext = await browser.newContext();
	const modPage = await modContext.newPage();
	await member(modPage.request, moderator, 'Mia Moderatorin');
	execFileSync('../api/bin/alvyo', ['user', 'role', moderator, 'moderator'], {
		env: {
			...process.env,
			ALVYO_DATABASE_URL:
				process.env.ALVYO_DATABASE_URL ??
				'postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable'
		}
	});
	await modPage.goto('/');
	await modPage.getByRole('link', { name: 'Moderation' }).click();
	const report = modPage.getByTestId('report').filter({ hasText: s });
	await expect(report).toContainText('Spam oder Werbung');
	await expect(report).toContainText(`@${troll}`);
	await report.getByRole('button', { name: 'Kommentar löschen' }).click();
	await expect(report).toHaveCount(0);
	await modContext.close();

	await page.reload();
	await page.getByTestId('tab-photos').click();
	await expect(page.getByTestId('comment').filter({ hasText: s })).toHaveCount(0);
});

test('reply to a comment, and edit one', async ({ page, browser }) => {
	const s = suffix();
	const owner = `own${s}`;
	await member(page.request, owner, 'Olga Owner');
	const created = await page.request.post('/api/v1/routes', {
		data: { title: `Gratweg ${s}`, visibility: 'public', ...routeContent(8.04, 46.665) }
	});
	const { id } = await created.json();
	const askContext = await browser.newContext();
	const ask = await askContext.newPage();
	const asker = `ask${s}`;
	await member(ask.request, asker, 'Anna Asker');

	await ask.goto(`/routes/${id}`);
	await ask.getByTestId('tab-photos').click();
	const social = ask.getByTestId('social');
	await social.getByLabel('Kommentar schreiben …').fill('Wie steil ist das?');
	await social.getByRole('button', { name: 'Kommentieren' }).click();
	await expect(social.getByTestId('comment')).toContainText('Wie steil ist das?');

	// The owner answers under the question; the asker hears of it.
	await page.goto(`/routes/${id}`);
	await page.getByTestId('tab-photos').click();
	const own = page.getByTestId('social');
	await own.getByTestId('comment').getByRole('button', { name: 'Antworten' }).click();
	await own.getByLabel('Deine Antwort …').fill('T3, mit Ketten.');
	await own.getByRole('button', { name: 'Antworten' }).last().click();
	await expect(own.getByTestId('replies').getByTestId('comment')).toContainText('T3, mit Ketten.');
	await mailMatching(`${asker}@example.ch`, /Olga Owner \(@own\w+\) hat auf deinen Kommentar/);

	// The asker edits the question; it says so.
	await ask.reload();
	await ask.getByTestId('tab-photos').click();
	const question = social.getByTestId('comment').first();
	await question.getByRole('button', { name: 'Bearbeiten' }).click();
	await question.getByLabel('Bearbeiten').fill('Wie steil ist das nach dem Gipfel?');
	await question.getByRole('button', { name: 'Speichern' }).click();
	await expect(question).toContainText('Wie steil ist das nach dem Gipfel?');
	await expect(question).toContainText('bearbeitet');
	// Nobody else can edit it.
	await page.reload();
	await page.getByTestId('tab-photos').click();
	await expect(own.getByRole('button', { name: 'Bearbeiten' })).toHaveCount(1); // the owner's reply
	await askContext.close();
});
