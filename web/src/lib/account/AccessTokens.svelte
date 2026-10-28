<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { primaryButtonSmall } from '#lib/components/actions.js';
	import { api, type AccessToken } from '#lib/api/client.js';
	import { m } from '#lib/paraglide/messages.js';
	import { focused } from '#lib/util/focus.js';
	import { Hydrated } from '#lib/util/hydrated.svelte.js';
	import { hikeDate } from '#lib/util/locale.js';

	// Personal access tokens for AI assistants (MCP) and alvyo-cli: they
	// only read. The token itself is shown once, right after creating it.
	const hydrated = new Hydrated();
	let tokens = $state<AccessToken[]>([]);
	let name = $state('');
	let created = $state('');
	let copied = $state(false);
	let revoking = $state<string>();
	let problem = $state('');
	const mcpUrl = $derived(`${page.url.origin}/api/v1/mcp`);

	onMount(async () => {
		const { data } = await api().GET('/me/tokens');
		tokens = data?.tokens ?? [];
	});

	async function create(e: SubmitEvent) {
		e.preventDefault();
		problem = '';
		const { data, response } = await api().POST('/me/tokens', { body: { name: name.trim() } });
		if (!data) {
			problem = response.status === 422 ? m.tokens_full() : m.error_generic();
			return;
		}
		const { token, ...rest } = data;
		tokens = [rest, ...tokens];
		created = token;
		copied = false;
		name = '';
	}

	async function copy() {
		await navigator.clipboard.writeText(created);
		copied = true;
	}

	async function revoke(id: string) {
		revoking = undefined;
		const { response } = await api().DELETE('/me/tokens/{id}', { params: { path: { id } } });
		if (response.ok) tokens = tokens.filter((t) => t.id !== id);
	}
</script>

<p class="text-sm text-stone-600">{m.tokens_intro()}</p>
<p class="mt-1 text-sm text-stone-600">
	{m.tokens_mcp()} <code class="break-all" data-testid="mcp-url">{mcpUrl}</code>
</p>

{#if created}
	<div
		class="mt-3 flex flex-col gap-2 rounded-md border border-accent bg-surface p-3 text-sm"
		data-testid="token-created"
	>
		<p role="status">{m.tokens_created()}</p>
		<div class="flex flex-wrap items-center gap-2">
			<code
				class="min-w-0 flex-1 rounded bg-stone-100 px-2 py-1 break-all"
				data-testid="token-value">{created}</code
			>
			<button
				type="button"
				class="rounded-md border border-stone-400 px-3 py-1 hover:bg-stone-100"
				onclick={copy}>{copied ? m.tokens_copied() : m.tokens_copy()}</button
			>
		</div>
		<p class="text-stone-600">{m.tokens_claude_code()}</p>
		<code class="rounded bg-stone-100 px-2 py-1 text-xs break-all"
			>claude mcp add --transport http alvyo {mcpUrl} --header "Authorization: Bearer {created}"</code
		>
	</div>
{/if}

<ul class="mt-2 flex flex-col gap-2 text-sm" data-testid="tokens">
	{#each tokens as t (t.id)}
		<li>
			<div class="flex items-center gap-3">
				<span class="flex-1"
					>{t.name}
					<span class="text-stone-500"
						>· {m.tokens_created_on({ date: hikeDate(t.created_at) })} · {t.last_used_at
							? m.tokens_used_on({ date: hikeDate(t.last_used_at) })
							: m.tokens_never_used()}</span
					></span
				>
				<button type="button" class="text-stone-500 underline" onclick={() => (revoking = t.id)}
					>{m.tokens_revoke()}</button
				>
			</div>
			{#if revoking === t.id}
				<div class="mt-1 flex flex-wrap items-center gap-2 text-xs" data-testid="revoke-confirm">
					<span class="flex-1">{m.tokens_revoke_confirm({ name: t.name })}</span>
					<button
						type="button"
						class="rounded bg-red-700 px-2 py-1 text-white"
						use:focused
						onclick={() => revoke(t.id)}>{m.tokens_revoke()}</button
					>
					<button type="button" class="underline" onclick={() => (revoking = undefined)}
						>{m.tokens_cancel()}</button
					>
				</div>
			{/if}
		</li>
	{/each}
</ul>

<form method="post" onsubmit={create} class="mt-2 flex flex-wrap items-center gap-2 text-sm">
	<input
		bind:value={name}
		required
		maxlength="60"
		placeholder={m.tokens_name_placeholder()}
		aria-label={m.tokens_name()}
		class="min-w-0 flex-1 rounded-md border border-stone-400 px-2 py-1"
		data-testid="token-name"
	/>
	<button
		disabled={!hydrated.value || !name.trim()}
		class={primaryButtonSmall}
		data-testid="token-create">{m.tokens_create()}</button
	>
</form>
{#if problem}<p role="alert" class="mt-1 text-sm text-red-700 dark:text-red-400">{problem}</p>{/if}
