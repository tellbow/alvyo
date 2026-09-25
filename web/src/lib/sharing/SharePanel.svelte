<script lang="ts">
	import { onMount } from 'svelte';
	import { api, type Grant } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import { choose } from '$lib/util/choose';
	import { Hydrated } from '$lib/util/hydrated.svelte';

	let {
		kind,
		id,
		verified
	}: {
		kind: 'routes' | 'journeys' | 'collections';
		id: string;
		/** Only verified accounts may invite. */
		verified: boolean;
	} = $props();

	// Until hydrated, a role picked in the menu would be reset to the default.
	const hydrated = new Hydrated();
	type Role = Grant['role'];
	let grants = $state<Grant[]>([]);
	let who = $state('');
	let role = $state<Role>('viewer');
	let error = $state('');
	let busy = $state(false);

	const path = () => ({ params: { path: { id } } });
	const grantPath = (grant: string) => ({ params: { path: { id, grant } } });

	// openapi-fetch needs literal paths, hence one branch per kind.
	const calls = {
		list: () =>
			kind === 'routes'
				? api().GET('/routes/{id}/grants', path())
				: kind === 'journeys'
					? api().GET('/journeys/{id}/grants', path())
					: api().GET('/collections/{id}/grants', path()),
		invite: (body: { username?: string; email?: string; role: Role }) =>
			kind === 'routes'
				? api().POST('/routes/{id}/grants', { ...path(), body })
				: kind === 'journeys'
					? api().POST('/journeys/{id}/grants', { ...path(), body })
					: api().POST('/collections/{id}/grants', { ...path(), body }),
		setRole: (grant: string, role: Role) =>
			kind === 'routes'
				? api().PATCH('/routes/{id}/grants/{grant}', { ...grantPath(grant), body: { role } })
				: kind === 'journeys'
					? api().PATCH('/journeys/{id}/grants/{grant}', { ...grantPath(grant), body: { role } })
					: api().PATCH('/collections/{id}/grants/{grant}', {
							...grantPath(grant),
							body: { role }
						}),
		remove: (grant: string) =>
			kind === 'routes'
				? api().DELETE('/routes/{id}/grants/{grant}', grantPath(grant))
				: kind === 'journeys'
					? api().DELETE('/journeys/{id}/grants/{grant}', grantPath(grant))
					: api().DELETE('/collections/{id}/grants/{grant}', grantPath(grant))
	};

	onMount(async () => {
		const { data } = await calls.list();
		grants = data?.grants ?? [];
	});

	function explain(status: number, detail?: string): string {
		if (status === 429) return m.share_rate();
		if (detail?.includes('no user')) return m.share_no_user();
		if (detail?.includes('yourself')) return m.share_self();
		if (detail?.includes('too many')) return m.share_too_many();
		if (status === 422) return m.share_bad_email();
		return m.error_generic();
	}

	async function run(
		call: Promise<{ data?: { grants: Grant[] }; error?: { detail?: string }; response: Response }>
	) {
		busy = true;
		error = '';
		const { data, error: err, response } = await call;
		busy = false;
		if (data) grants = data.grants;
		else error = explain(response.status, err?.detail);
		return !!data;
	}

	async function invite(e: SubmitEvent) {
		e.preventDefault();
		const w = who.trim();
		const body = w.includes('@') && !w.startsWith('@') ? { email: w, role } : { username: w, role };
		const ok = await run(calls.invite(body));
		if (ok) who = '';
	}

	const setRole = (g: Grant, r: Role) => run(calls.setRole(g.id, r));
	const remove = (g: Grant) => run(calls.remove(g.id));
</script>

<section class="flex flex-col gap-2 text-sm" data-testid="share-panel">
	<h3 class="font-medium">{m.share_people()}</h3>
	{#if grants.length > 0}
		<ul class="flex flex-col gap-1">
			{#each grants as g (g.id)}
				<li class="flex items-center gap-2" data-testid="grant">
					<span class="min-w-0 flex-1 truncate">
						{#if g.username}
							{g.display_name} <span class="text-stone-500">@{g.username}</span>
						{:else}
							{g.email} <span class="text-xs text-stone-500">· {m.share_pending()}</span>
						{/if}
					</span>
					<select
						class="rounded border border-stone-300 px-1 py-0.5 text-xs"
						value={g.role}
						aria-label={m.share_role()}
						use:choose={(v) => setRole(g, v as Role)}
					>
						<option value="viewer">{m.role_viewer()}</option>
						<option value="editor">{m.role_editor()}</option>
					</select>
					<button
						type="button"
						class="text-xs text-stone-500 underline"
						onclick={() => remove(g)}
						aria-label={m.share_remove()}>✕</button
					>
				</li>
			{/each}
		</ul>
	{/if}
	{#if verified}
		<form method="post" onsubmit={invite} class="flex flex-wrap gap-1">
			<input
				bind:value={who}
				disabled={!hydrated.value}
				required
				maxlength="254"
				placeholder={m.share_who()}
				aria-label={m.share_who()}
				class="min-w-0 flex-1 rounded border border-stone-300 px-2 py-1"
			/>
			<select
				bind:value={role}
				disabled={!hydrated.value}
				class="rounded border border-stone-300 px-1"
				aria-label={m.share_role()}
			>
				<option value="viewer">{m.role_viewer()}</option>
				<option value="editor">{m.role_editor()}</option>
			</select>
			<button
				disabled={busy || !hydrated.value}
				class="rounded bg-accent px-2 py-1 text-on-accent hover:bg-accent-hover disabled:opacity-50"
			>
				{m.share_invite()}
			</button>
		</form>
		<p class="text-xs text-stone-500">{m.share_hint()}</p>
	{:else}
		<p class="text-xs text-stone-500">{m.share_needs_verify()}</p>
	{/if}
	{#if error}<p role="alert" class="text-xs text-red-700 dark:text-red-400">{error}</p>{/if}
</section>
