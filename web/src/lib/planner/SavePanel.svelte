<script lang="ts">
	import { Hydrated } from '$lib/util/hydrated.svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { api, type Me, type Route } from '$lib/api/client';
	import { m } from '$lib/paraglide/messages';
	import TagInput from '$lib/tags/TagInput.svelte';
	import type { Planner } from './planner.svelte';

	let { planner, user, route }: { planner: Planner; user: Me; route?: Route } = $props();
	const hydrated = new Hydrated();
	// Editors change the route, not who sees it.
	const isOwner = $derived(!route || route.role === 'owner');

	type Visibility = 'private' | 'unlisted' | 'public';

	// Editable copies of the route's metadata, seeded once from the loaded route.
	// svelte-ignore state_referenced_locally
	let title = $state(route?.title ?? '');
	// svelte-ignore state_referenced_locally
	let visibility = $state<Visibility>((route?.visibility as Visibility) ?? 'private');
	// svelte-ignore state_referenced_locally
	let tags = $state<string[]>(route?.tags ?? []);
	// svelte-ignore state_referenced_locally
	let version = $state(route?.version ?? 0);
	// svelte-ignore state_referenced_locally
	let shareToken = $state(route?.share_token ?? '');
	// svelte-ignore state_referenced_locally
	let savedMeta = $state(
		JSON.stringify([route?.title ?? '', route?.visibility ?? 'private', route?.tags ?? []])
	);
	let status = $state<'idle' | 'saving' | 'saved' | 'conflict' | 'failed'>('idle');
	let copied = $state(false);

	const metaDirty = $derived(JSON.stringify([title, visibility, tags]) !== savedMeta);
	const canSave = $derived(
		title.trim() !== '' &&
			planner.complete &&
			(!route || planner.dirty || metaDirty) &&
			status !== 'saving'
	);
	// Shown once the route is saved as unlisted.
	const shareUrl = $derived(
		route && shareToken && visibility === 'unlisted' && !metaDirty
			? `${page.url.origin}/routes/${route.id}?t=${shareToken}`
			: ''
	);

	async function copy() {
		await navigator.clipboard.writeText(shareUrl);
		copied = true;
	}

	async function rotate() {
		if (!route) return;
		const { data } = await api().POST('/routes/{id}/link/rotate', {
			params: { path: { id: route.id } }
		});
		if (data) {
			shareToken = data.share_token;
			copied = false;
		}
	}

	async function save(e: SubmitEvent) {
		e.preventDefault();
		status = 'saving';
		// What is sent is what counts as saved: changes made meanwhile stay unsaved.
		const saving = planner.fingerprint();
		const meta = JSON.stringify([title, visibility, tags]);
		const content = planner.content();
		try {
			if (!route) {
				const { data } = await api().POST('/routes', {
					body: { title: title.trim(), visibility, tags, ...content }
				});
				if (!data) {
					status = 'failed';
					return;
				}
				planner.markSaved(saving);
				await goto(resolve('/plan/[id]', { id: data.id }), { replaceState: true });
				return;
			}
			const { data, response } = await api().PATCH('/routes/{id}', {
				params: { path: { id: route.id }, header: { 'If-Match': `"${version}"` } },
				body: {
					title: title.trim(),
					tags,
					...(isOwner ? { visibility } : {}),
					...(planner.dirty ? content : {})
				}
			});
			if (data) {
				version = data.version;
				shareToken = data.share_token ?? '';
				savedMeta = meta;
				planner.markSaved(saving);
				status = 'saved';
			} else {
				status = response.status === 412 ? 'conflict' : 'failed';
			}
		} catch {
			status = 'failed'; // no connection
		}
	}
</script>

<form
	method="post"
	onsubmit={save}
	class="flex flex-col gap-2 rounded-md border border-stone-200 p-3"
	data-testid="save-panel"
>
	<label class="flex flex-col gap-1 text-sm">
		<span class="font-medium">{m.field_title()}</span>
		<input
			bind:value={title}
			required
			maxlength="120"
			class="rounded-md border border-stone-300 px-2 py-1.5"
		/>
	</label>
	<div class="flex flex-col gap-1 text-sm">
		<span class="font-medium">{m.tags_label()}</span>
		<TagInput bind:tags />
	</div>
	{#if isOwner}
		<label class="flex flex-col gap-1 text-sm">
			<span class="font-medium">{m.field_visibility()}</span>
			<select bind:value={visibility} class="rounded-md border border-stone-300 px-2 py-1.5">
				<option value="private">{m.visibility_private()}</option>
				<option value="unlisted" disabled={!user.email_verified}>{m.visibility_unlisted()}</option>
				<option value="public" disabled={!user.email_verified}>{m.visibility_public()}</option>
			</select>
		</label>
		{#if !user.email_verified}
			<p class="text-xs text-stone-500">{m.visibility_needs_verify()}</p>
		{/if}
	{:else if route}
		<p class="text-xs text-stone-500">{m.shared_editor_note({ user: route.owner_username })}</p>
	{/if}
	<button
		disabled={!hydrated.value || !canSave}
		class="rounded-md bg-accent px-3 py-1.5 text-sm text-on-accent hover:bg-accent-hover disabled:opacity-50"
	>
		{status === 'saving' ? m.saving() : m.save()}
	</button>
	{#if shareUrl}
		<div class="flex flex-col gap-1 text-xs" data-testid="share-link">
			<span class="font-medium">{m.share_link()}</span>
			<div class="flex gap-1">
				<input
					readonly
					value={shareUrl}
					class="min-w-0 flex-1 rounded border border-stone-300 px-1.5 py-1"
				/>
				<button type="button" class="rounded px-2 ring-1 ring-stone-300" onclick={copy}>
					{copied ? m.share_copied() : m.share_copy()}
				</button>
			</div>
			<button
				type="button"
				class="self-start text-stone-600 underline"
				title={m.share_rotate_hint()}
				onclick={rotate}
			>
				{m.share_rotate()}
			</button>
		</div>
	{/if}
	{#if route && !planner.dirty}
		<!-- API download, not a page: resolve() does not apply. -->
		<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
		<a href="/api/v1/routes/{route.id}/gpx" download class="text-xs text-accent-ink underline"
			>{m.route_gpx()}</a
		>
	{/if}
	{#if status === 'saved' && !planner.dirty && !metaDirty}
		<p class="text-xs text-accent-ink" role="status">{m.saved()}</p>
	{:else if status === 'conflict'}
		<p class="text-xs text-red-700 dark:text-red-400" role="alert">{m.save_conflict()}</p>
	{:else if status === 'failed'}
		<p class="text-xs text-red-700 dark:text-red-400" role="alert">{m.save_failed()}</p>
	{:else if !planner.complete && planner.anchors.length > 1}
		<p class="text-xs text-stone-500">{m.save_incomplete()}</p>
	{/if}
</form>
