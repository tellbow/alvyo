import type { APIRequestContext } from '@playwright/test';
import { signUp } from './accounts';
import { expect, test } from './fixtures';
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

test('find someone, ask, be accepted; a private profile through its invite link', async ({
	page,
	browser
}) => {
	const s = suffix();
	const [anna, beat, carla] = [`ann${s}`, `bea${s}`, `car${s}`];
	await member(page.request, anna, `Anna ${s}`);
	const beatContext = await browser.newContext();
	const beatPage = await beatContext.newPage();
	await member(beatPage.request, beat, `Beat ${s}`);

	// Anna finds Beat by name and asks.
	await page.goto('/friends');
	await page.getByTestId('friends-search').fill(`Beat ${s}`);
	const found = page.getByTestId('friends-found').getByTestId('found');
	await expect(found).toContainText(`@${beat}`);
	await found.getByRole('button', { name: 'Als Freund hinzufügen' }).click();
	await expect(found.getByTestId('friend')).toHaveAttribute('data-friend', 'requested');
	await mailMatching(`${beat}@example.ch`, new RegExp(`Anna ${s} \\(@${anna}\\) möchte`));

	// Beat sees the request in the header and accepts.
	await beatPage.goto('/');
	await expect(beatPage.getByTestId('nav-friends').first()).toContainText('1');
	await beatPage.goto('/friends');
	const incoming = beatPage.getByTestId('friends-incoming').getByTestId('incoming');
	await incoming.getByRole('button', { name: 'Annehmen' }).click();
	await expect(beatPage.getByTestId('friends-list')).toContainText(`Anna ${s}`);

	// Beat goes private: Carla does not find him, but his link makes them
	// friends.
	await beatPage.goto('/account');
	// Saved before leaving: the next page load would cancel the request.
	const saved = beatPage.waitForResponse(
		(r) => r.url().endsWith('/api/v1/me') && r.request().method() === 'PATCH'
	);
	await beatPage.getByTestId('profile-public').uncheck();
	expect((await saved).ok()).toBe(true);
	await expect(beatPage.getByTestId('profile-public')).not.toBeChecked();
	const { token } = await (await beatPage.request.get('/api/v1/me/friend-link')).json();
	const link = `/friends/invite/${token}`;
	// The link goes out with a sentence saying what to do with it (feedback issue 63).
	await beatPage.addInitScript(() => {
		navigator.share = async (d) => {
			(window as unknown as { shared: ShareData }).shared = d!;
		};
	});
	await beatPage.goto('/friends');
	await beatPage.getByTestId('friend-invite-link').click();
	const shared = await beatPage.evaluate(() => (window as unknown as { shared: ShareData }).shared);
	expect(shared.text).toContain('tippe auf «Annehmen»');
	expect(shared.url).toMatch(new RegExp(`${link}$`));

	const carlaContext = await browser.newContext();
	const carlaPage = await carlaContext.newPage();
	await member(carlaPage.request, carla, `Carla ${s}`);
	await carlaPage.goto('/friends');
	await carlaPage.getByTestId('friends-search').fill(`Beat ${s}`);
	await expect(carlaPage.getByText('Niemand gefunden.')).toBeVisible();
	await carlaPage.goto(link);
	await expect(carlaPage.getByTestId('friend-invite')).toContainText(
		`Beat ${s} möchte mit dir befreundet sein`
	);
	await carlaPage.getByTestId('friend-invite-accept').click();
	await expect(carlaPage.getByRole('status')).toHaveText('Ihr seid jetzt Freunde.');
	await carlaPage.goto('/friends');
	await expect(carlaPage.getByTestId('friends-list')).toContainText(`Beat ${s}`);

	// Anna is Beat's friend too: suggested to Carla by the number in common
	// only, until Carla does not want her suggested.
	const suggested = carlaPage.getByTestId('friends-suggested').getByTestId('suggested');
	await expect(suggested).toContainText(`Anna ${s}`);
	await expect(suggested).toContainText('1 gemeinsamer Freund');
	await expect(suggested).not.toContainText('Beat');
	await suggested.getByRole('button', { name: 'Nicht vorschlagen' }).click();
	await expect(carlaPage.getByTestId('friends-suggested')).toHaveCount(0);
	await carlaPage.reload();
	await expect(carlaPage.getByTestId('friends-list')).toContainText(`Beat ${s}`);
	await expect(carlaPage.getByTestId('friends-suggested')).toHaveCount(0);
	await beatContext.close();
	await carlaContext.close();
});
