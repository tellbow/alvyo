<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { refused, when, type AdminUser } from '#lib/admin/admin.js';
	import Search from '#lib/admin/Search.svelte';
	import UndoBar from '#lib/admin/UndoBar.svelte';
	import { adminApi } from '#lib/api/client.js';
	import Seo from '#lib/seo/Seo.svelte';

	let { data } = $props();
	const isAdmin = $derived(data.user?.role === 'admin');
	const count = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
	let done = $state<{ text: string; logId?: string }>();
	let error = $state('');

	type Action = 'ban' | 'unban' | 'logout' | 'verification';
	const doneText: Record<Action, (u: AdminUser) => string> = {
		ban: (u) => `@${u.username} gesperrt, Inhalte privat.`,
		unban: (u) => `@${u.username} entsperrt.`,
		logout: (u) => `@${u.username} überall abgemeldet.`,
		verification: (u) => `Bestätigungs-E-Mail an ${u.email} gesendet.`
	};

	async function act(u: AdminUser, action: Action) {
		error = '';
		const path = `/admin/users/{id}/${action}` as const;
		const { data: r, response } = await adminApi().POST(path, { params: { path: { id: u.id } } });
		if (!r) return void (error = refused(response.status));
		// Sessions and e-mails cannot be taken back.
		done = {
			text: doneText[action](u),
			logId: action === 'ban' || action === 'unban' ? r.log_id : undefined
		};
		await invalidateAll();
	}

	async function setRole(u: AdminUser, role: AdminUser['role']) {
		error = '';
		const { data: r, response } = await adminApi().PUT('/admin/users/{id}/role', {
			params: { path: { id: u.id } },
			body: { role }
		});
		if (!r) return void (error = refused(response.status));
		done = { text: `@${u.username} ist jetzt ${role}.`, logId: r.log_id };
		await invalidateAll();
	}
</script>

<Seo title="Nutzer" index={false} />

<div class="mx-auto w-full max-w-4xl px-4 py-8">
	<h1 class="mb-4 text-2xl font-semibold">Nutzer</h1>
	<Search label="Nutzer suchen" placeholder="Name, Benutzername oder E-Mail" />
	<UndoBar bind:done />
	{#if error}<p role="alert" class="mb-4 text-sm text-red-700 dark:text-red-400">{error}</p>{/if}

	{#if data.users.length === 0}
		<p class="text-stone-600">Niemand gefunden.</p>
	{/if}
	<ul class="flex flex-col gap-3" data-testid="admin-users">
		{#each data.users as u (u.id)}
			<li
				class="rounded-xl border border-stone-200 bg-surface p-4 text-sm"
				data-testid="admin-user"
			>
				<div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
					<span class="text-base font-semibold">{u.display_name}</span>
					<span class="text-stone-600">@{u.username}</span>
					{#if u.role !== 'user'}
						<span class="rounded bg-stone-200 px-1.5 py-0.5 text-xs font-semibold">{u.role}</span>
					{/if}
					{#if u.banned_at}
						<span class="rounded bg-red-700 px-1.5 py-0.5 text-xs font-semibold text-white"
							>gesperrt seit {when(u.banned_at)}</span
						>
					{/if}
				</div>
				<p class="mt-1 text-stone-600">
					{u.email} · {u.email_verified ? 'bestätigt' : 'nicht bestätigt'} · dabei seit {when(
						u.created_at
					)}{#if u.last_seen_at}
						· zuletzt {when(u.last_seen_at)}{/if}
				</p>
				<p class="mt-1 text-stone-600">
					<a
						class="underline"
						href={`${resolve('/admin/(portal)/inhalte')}?q=${encodeURIComponent(u.username)}`}
						>{count(u.routes, 'Route', 'Routen')} · {count(
							u.journeys,
							'Etappentour',
							'Etappentouren'
						)} · {count(u.collections, 'Sammlung', 'Sammlungen')}</a
					>
					· {count(u.sessions, 'Sitzung', 'Sitzungen')}
				</p>
				<div class="mt-3 flex flex-wrap items-center gap-2">
					{#if u.banned_at}
						<button
							type="button"
							class="rounded px-2 py-1 ring-1 ring-stone-300"
							onclick={() => act(u, 'unban')}>Entsperren</button
						>
					{:else if u.role === 'user'}
						<button
							type="button"
							class="rounded bg-red-700 px-2 py-1 text-white"
							onclick={() => act(u, 'ban')}>Sperren</button
						>
					{/if}
					{#if u.sessions > 0}
						<button
							type="button"
							class="rounded px-2 py-1 ring-1 ring-stone-300"
							onclick={() => act(u, 'logout')}>Überall abmelden</button
						>
					{/if}
					{#if !u.email_verified}
						<button
							type="button"
							class="rounded px-2 py-1 ring-1 ring-stone-300"
							onclick={() => act(u, 'verification')}>Bestätigungs-E-Mail senden</button
						>
					{/if}
					{#if isAdmin && u.username !== data.user?.username}
						<label class="ml-auto flex items-center gap-2">
							Rolle
							<select
								value={u.role}
								class="rounded border border-stone-300 bg-surface px-2 py-1"
								onchange={(e) => setRole(u, e.currentTarget.value as AdminUser['role'])}
							>
								<option value="user">user</option>
								<option value="moderator">moderator</option>
								<option value="admin">admin</option>
							</select>
						</label>
					{/if}
				</div>
			</li>
		{/each}
	</ul>
</div>
