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
	await beatPage.goto('/friends');
	const link = await beatPage.getByTestId('friend-link').locator('input').inputValue();

	const carlaContext = await browser.newContext();
	const carlaPage = await carlaContext.newPage();
	await member(carlaPage.request, carla, `Carla ${s}`);
	await carlaPage.goto('/friends');
	await carlaPage.getByTestId('friends-search').fill(`Beat ${s}`);
	await expect(carlaPage.getByText('Niemand gefunden.')).toBeVisible();
	await carlaPage.goto(link);
	await expect(carlaPage.getByTestId('friend-invite')).toContainText(`Beat ${s} lädt dich ein`);
	await carlaPage.getByTestId('friend-invite-accept').click();
	await expect(carlaPage.getByRole('status')).toHaveText('Ihr seid jetzt Freunde.');
	await carlaPage.goto('/friends');
	await expect(carlaPage.getByTestId('friends-list')).toContainText(`Beat ${s}`);
	await beatContext.close();
	await carlaContext.close();
});
