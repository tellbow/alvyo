import { execFileSync } from 'node:child_process';
import { signUp } from './accounts';
import { expect, test } from './fixtures';
import { routeContent } from './legs';

// The admin portal (feedback issues 70, 72): find someone, ban them, undo it,
// make an item private, and see it all in «Verlauf».
test('admin portal: users, items and the log with undo', async ({ page, browser }) => {
	const s = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;
	const troll = `trl${s}`;
	const trollContext = await browser.newContext();
	for (const [request, name] of [
		[trollContext.request, troll],
		[page.request, `mod${s}`]
	] as const) {
		const res = await signUp(request, {
			data: {
				email: `${name}@example.ch`,
				username: name,
				display_name: name,
				password: 'sehr-geheim-123'
			}
		});
		expect(res.status()).toBe(200);
	}
	await trollContext.request.post('/api/v1/routes', {
		data: { title: `Werbung ${s}`, visibility: 'public', ...routeContent(8.05, 46.665) }
	});
	await trollContext.close();
	execFileSync('../api/bin/alvyo', ['user', 'role', `mod${s}`, 'moderator'], {
		env: {
			...process.env,
			ALVYO_DATABASE_URL:
				process.env.ALVYO_DATABASE_URL ??
				'postgres://alvyo:alvyo@localhost:5432/alvyo?sslmode=disable'
		}
	});

	// Nutzer: ban, and take it back right away.
	await page.goto(`/admin/nutzer?q=${troll}`);
	const user = page.getByTestId('admin-user').filter({ hasText: `@${troll}` });
	await expect(user).toContainText('1 Route ·');
	await user.getByRole('button', { name: 'Sperren' }).click();
	await expect(page.getByTestId('admin-done')).toContainText(`@${troll} gesperrt`);
	await expect(user).toContainText('gesperrt seit');
	await page.getByTestId('admin-done').getByRole('button', { name: 'Rückgängig' }).click();
	await expect(page.getByTestId('admin-done')).toContainText('Rückgängig gemacht.');
	await expect(user.getByRole('button', { name: 'Sperren' })).toBeVisible();

	// Inhalte: their route, made private.
	await user.getByRole('link', { name: /Route/ }).click();
	const item = page.getByTestId('admin-item').filter({ hasText: `Werbung ${s}` });
	await expect(item).toContainText('öffentlich');
	await item.getByRole('button', { name: 'Privat machen' }).click();
	await expect(item).toContainText('privat');

	// Verlauf: newest first; the undone ban struck through, the rest undoable.
	await page.goto('/admin/verlauf?area=nutzer');
	const ban = page.getByTestId('admin-log-entry').filter({ hasText: `@${troll} gesperrt` });
	await expect(ban).toContainText('rückgängig gemacht');
	await page.goto('/admin/verlauf?area=inhalte');
	const unpublished = page
		.getByTestId('admin-log-entry')
		.filter({ hasText: `«Werbung ${s}» privat gemacht` });
	await unpublished.getByRole('button', { name: 'Rückgängig' }).click();
	await expect(unpublished).toContainText('rückgängig gemacht');
});
